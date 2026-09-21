#!/usr/bin/env python3
"""Compile Mica JSON policy configurations into an Alloy analysis module."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


class CompileError(ValueError):
    pass


RIGHTS = {"R": "ReadAccess", "W": "WriteAccess", "X": "ExecAccess"}
MEM_TYPES = {"PROTECTED": "Protected", "UNPROTECTED": "Unprotected"}
TRANSITION_TYPES = {"CALL": "Call", "EXCEPTION": "Exception"}
ACTIONS = {"ALLOW": "Allow", "SCRUB": "Scrub", "BLOCK": "Block"}


def identifier(prefix: str, value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_]", "_", str(value))
    if not cleaned or cleaned[0].isdigit():
        cleaned = "_" + cleaned
    return prefix + cleaned


def alloy_set(atoms: list[str] | set[str]) -> str:
    values = sorted(atoms)
    return "none" if not values else " + ".join(values)


def parse_rights(value: Any, context: str) -> list[str]:
    if isinstance(value, list):
        tokens = [str(item).upper() for item in value]
    elif isinstance(value, str):
        compact = value.upper().replace(" ", "")
        tokens = list(compact)
    else:
        raise CompileError(f"{context}: prot must be a string or list")

    invalid = sorted(set(tokens) - set(RIGHTS))
    if invalid:
        raise CompileError(f"{context}: unsupported access rights {invalid}")
    if not tokens:
        raise CompileError(f"{context}: a mapping must grant at least one right")
    return sorted(set(tokens))


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise CompileError(f"{path}: {error}") from error
    if not isinstance(value, dict):
        raise CompileError(f"{path}: top-level JSON value must be an object")
    return value


@dataclass
class Aliases:
    peers: dict[str, str] = field(default_factory=dict)
    channels: dict[str, str] = field(default_factory=dict)
    policies: dict[str, str] = field(default_factory=dict)

    @classmethod
    def load(cls, path: Path | None) -> "Aliases":
        if path is None:
            return cls()
        raw = load_json(path)
        result = cls()
        for name in ("peers", "channels", "policies"):
            section = raw.get(name, {})
            if not isinstance(section, dict) or not all(
                isinstance(key, str) and isinstance(value, str)
                for key, value in section.items()
            ):
                raise CompileError(
                    f"{path}: manifest section {name!r} must map strings to strings"
                )
            setattr(result, name, section)
        return result

    @staticmethod
    def resolve(mapping: dict[str, str], source: Path, local: str) -> str:
        qualified = f"{source.stem}:{local}"
        return mapping.get(qualified, mapping.get(local, local))


@dataclass
class Spec:
    atom: str
    channel: str
    can_read: set[str] = field(default_factory=set)
    can_write: set[str] = field(default_factory=set)
    can_exec: set[str] = field(default_factory=set)
    any_mappings: list[str] = field(default_factory=list)


@dataclass
class AnyEntry:
    atom: str
    count: int
    access: str


@dataclass
class Transition:
    atom: str
    owner: str
    transition_type: str
    ids: set[str]
    action: str


@dataclass
class PolicyData:
    atom: str
    peers: set[str]
    strict_peers: set[str]
    specs: list[Spec]
    transitions: list[Transition]


@dataclass
class Deployment:
    peers: set[str] = field(default_factory=set)
    channels: dict[str, str] = field(default_factory=dict)
    policies: list[PolicyData] = field(default_factory=list)
    any_entries: list[AnyEntry] = field(default_factory=list)
    transition_ids: set[str] = field(default_factory=set)
    gateway_values: dict[str, bool] = field(default_factory=dict)
    ignored_fields: set[str] = field(default_factory=set)


class Compiler:
    def __init__(self, aliases: Aliases):
        self.aliases = aliases
        self.deployment = Deployment()
        self._atom_origins: dict[str, str] = {}

    def unique_atom(self, prefix: str, logical_name: str, origin: str) -> str:
        atom = identifier(prefix, logical_name)
        previous = self._atom_origins.get(atom)
        if previous is not None and previous != origin:
            raise CompileError(
                f"Alloy identifier collision: {origin!r} and {previous!r} both become {atom}"
            )
        self._atom_origins[atom] = origin
        return atom

    def peer_atom(self, source: Path, local: str) -> str:
        global_name = Aliases.resolve(self.aliases.peers, source, local)
        atom = identifier("Peer_", global_name)
        self.deployment.peers.add(atom)
        return atom

    def channel_atom(self, source: Path, local: str, mem_type: str) -> str:
        global_name = Aliases.resolve(self.aliases.channels, source, local)
        atom = identifier("Channel_", global_name)
        previous = self.deployment.channels.get(atom)
        if previous is not None and previous != mem_type:
            raise CompileError(
                f"channel {global_name!r} is both {previous} and {mem_type}"
            )
        self.deployment.channels[atom] = mem_type
        return atom

    def compile_file(self, path: Path) -> None:
        raw = load_json(path)
        peers_raw = raw.get("Peers")
        if not isinstance(peers_raw, dict):
            raise CompileError(f"{path}: Peers must be an object")

        self_local = peers_raw.get("Self")
        if not isinstance(self_local, str):
            raise CompileError(f"{path}: Peers.Self must be a peer identifier")

        policy_name = self.aliases.policies.get(path.stem, path.stem)
        policy_atom = self.unique_atom(
            "Policy_", policy_name, f"policy file {path}"
        )

        local_peers: dict[str, str] = {}
        strict_peers: set[str] = set()
        named_peers: set[str] = set()

        for local, properties in peers_raw.items():
            if local == "Self":
                continue
            if not isinstance(properties, dict):
                raise CompileError(f"{path}: Peers.{local} must be an object")
            atom = self.peer_atom(path, local)
            local_peers[local] = atom
            named_peers.add(atom)

            strict = properties.get("strict", False)
            if not isinstance(strict, bool):
                raise CompileError(f"{path}: Peers.{local}.strict must be boolean")
            if strict:
                strict_peers.add(atom)

            gateway = properties.get("is_gateway")
            if gateway is not None:
                if not isinstance(gateway, bool):
                    raise CompileError(
                        f"{path}: Peers.{local}.is_gateway must be boolean"
                    )
                previous = self.deployment.gateway_values.get(atom)
                if previous is not None and previous != gateway:
                    raise CompileError(
                        f"{path}: conflicting is_gateway values for {local}"
                    )
                self.deployment.gateway_values[atom] = gateway

            for ignored in set(properties) - {"hash", "is_gateway", "strict"}:
                self.deployment.ignored_fields.add(f"Peers.*.{ignored}")
            if "hash" in properties:
                self.deployment.ignored_fields.add("Peers.*.hash")

        if self_local not in local_peers:
            local_peers[self_local] = self.peer_atom(path, self_local)
            named_peers.add(local_peers[self_local])

        def resolve_peer(local: str, context: str) -> str:
            if local.upper() == "SELF":
                local = self_local
            atom = local_peers.get(local)
            if atom is None:
                raise CompileError(f"{path}: {context} references unknown peer {local!r}")
            return atom

        specs: list[Spec] = []
        channels_raw = raw.get("MemChannels", {})
        if not isinstance(channels_raw, dict):
            raise CompileError(f"{path}: MemChannels must be an object")

        for channel_local, channel_raw in channels_raw.items():
            if not isinstance(channel_raw, dict):
                raise CompileError(f"{path}: MemChannels.{channel_local} must be an object")
            type_raw = str(channel_raw.get("type", "")).upper()
            if type_raw not in MEM_TYPES:
                raise CompileError(
                    f"{path}: MemChannels.{channel_local}.type must be PROTECTED or UNPROTECTED"
                )
            channel_atom = self.channel_atom(
                path, channel_local, MEM_TYPES[type_raw]
            )
            spec_atom = self.unique_atom(
                "Spec_",
                f"{policy_name}_{channel_local}",
                f"{path}:MemChannels.{channel_local}",
            )
            spec = Spec(atom=spec_atom, channel=channel_atom)

            mappings = channel_raw.get("mappings", {})
            if not isinstance(mappings, dict):
                raise CompileError(
                    f"{path}: MemChannels.{channel_local}.mappings must be an object"
                )

            for mapping_name, mapping_raw in mappings.items():
                if not isinstance(mapping_raw, dict):
                    raise CompileError(
                        f"{path}: mapping {channel_local}.{mapping_name} must be an object"
                    )
                context = f"{path}: mapping {channel_local}.{mapping_name}"
                rights = parse_rights(mapping_raw.get("prot"), context)
                if mapping_name.upper() == "ANY":
                    count = mapping_raw.get("count")
                    if not isinstance(count, int) or isinstance(count, bool):
                        raise CompileError(f"{context}: count must be an integer")
                    for right in rights:
                        any_atom = self.unique_atom(
                            "Any_",
                            f"{policy_name}_{channel_local}_{right}",
                            f"{context}:{right}",
                        )
                        self.deployment.any_entries.append(
                            AnyEntry(any_atom, count, RIGHTS[right])
                        )
                        spec.any_mappings.append(any_atom)
                else:
                    peer = resolve_peer(mapping_name, context)
                    if "R" in rights:
                        spec.can_read.add(peer)
                    if "W" in rights:
                        spec.can_write.add(peer)
                    if "X" in rights:
                        spec.can_exec.add(peer)

                for ignored in set(mapping_raw) - {"prot", "count"}:
                    self.deployment.ignored_fields.add(f"MemChannels.*.mappings.*.{ignored}")

            for ignored in set(channel_raw) - {"type", "mappings"}:
                self.deployment.ignored_fields.add(f"MemChannels.*.{ignored}")
            specs.append(spec)

        transitions: list[Transition] = []
        transitions_raw = raw.get("TransChannels", {})
        if not isinstance(transitions_raw, dict):
            raise CompileError(f"{path}: TransChannels must be an object")

        for local, transition_raw in transitions_raw.items():
            if not isinstance(transition_raw, dict):
                raise CompileError(f"{path}: TransChannels.{local} must be an object")
            context = f"{path}: TransChannels.{local}"
            owner_raw = transition_raw.get("owner")
            if not isinstance(owner_raw, str):
                raise CompileError(f"{context}.owner must be a peer identifier")
            owner = resolve_peer(owner_raw, context)
            type_raw = str(transition_raw.get("type", "")).upper()
            if type_raw not in TRANSITION_TYPES:
                raise CompileError(f"{context}.type must be call or exception")
            action_raw = str(transition_raw.get("policy", "")).upper()
            if action_raw not in ACTIONS:
                raise CompileError(f"{context}.policy must be ALLOW, SCRUB, or BLOCK")
            range_raw = transition_raw.get("range")
            if not isinstance(range_raw, list) or not range_raw:
                raise CompileError(f"{context}.range must be a non-empty list")
            ids = {
                identifier("TransitionID_", f"{type_raw}_{value}")
                for value in range_raw
            }
            self.deployment.transition_ids.update(ids)
            atom = self.unique_atom(
                "Transition_", f"{policy_name}_{local}", context
            )
            transitions.append(
                Transition(
                    atom,
                    owner,
                    TRANSITION_TYPES[type_raw],
                    ids,
                    ACTIONS[action_raw],
                )
            )

        for ignored in set(raw) - {"Peers", "MemChannels", "TransChannels"}:
            self.deployment.ignored_fields.add(ignored)

        self.deployment.policies.append(
            PolicyData(policy_atom, named_peers, strict_peers, specs, transitions)
        )

    def emit(self, module_name: str) -> str:
        deployment = self.deployment
        specs = [spec for policy in deployment.policies for spec in policy.specs]
        transitions = [
            transition
            for policy in deployment.policies
            for transition in policy.transitions
        ]

        lines = [
            f"module {module_name}",
            "",
            "open models/mica/core",
            "open models/mica/relations",
            "open models/mica/constraints",
            "",
            "// Generated by tools/mica-json-to-alloy/mica_json_to_alloy.py.",
            "// Edit the source JSON rather than this file.",
        ]
        if deployment.ignored_fields:
            lines.append(
                "// Not represented by the current Alloy model: "
                + ", ".join(sorted(deployment.ignored_fields))
            )
        lines.append("")

        declarations = [
            ("Peer", sorted(deployment.peers)),
            ("MemChannel", sorted(deployment.channels)),
            ("Policy", [policy.atom for policy in deployment.policies]),
            ("MemChannelSpec", [spec.atom for spec in specs]),
            ("AnyMapping", [entry.atom for entry in deployment.any_entries]),
            ("TransitionChannel", [transition.atom for transition in transitions]),
            ("TransitionID", sorted(deployment.transition_ids)),
        ]
        for parent, atoms in declarations:
            if atoms:
                lines.append(f"one sig {', '.join(atoms)} extends {parent} {{}}")
        lines.extend(["", "pred configuration {"])

        exact_sets = [
            ("Peer", deployment.peers),
            ("MemChannel", set(deployment.channels)),
            ("Policy", {policy.atom for policy in deployment.policies}),
            ("MemChannelSpec", {spec.atom for spec in specs}),
            ("AnyMapping", {entry.atom for entry in deployment.any_entries}),
            ("TransitionChannel", {transition.atom for transition in transitions}),
            ("TransitionID", deployment.transition_ids),
        ]
        for signature, atoms in exact_sets:
            lines.append(f"  {signature} = {alloy_set(atoms)}")

        declared_gateways = {
            peer for peer, value in deployment.gateway_values.items() if value
        }
        lines.append(f"  Gateway = {alloy_set(declared_gateways)}")
        lines.append("")

        for channel, mem_type in sorted(deployment.channels.items()):
            lines.append(f"  {channel}.memType = {mem_type}")
        if deployment.channels:
            lines.append("")

        for policy in deployment.policies:
            lines.extend(
                [
                    f"  {policy.atom}.peers = {alloy_set(policy.peers)}",
                    f"  {policy.atom}.strictPeers = {alloy_set(policy.strict_peers)}",
                    f"  {policy.atom}.memChannels = {alloy_set({s.atom for s in policy.specs})}",
                    f"  {policy.atom}.transitions = {alloy_set({t.atom for t in policy.transitions})}",
                    "",
                ]
            )

        for spec in specs:
            lines.extend(
                [
                    f"  {spec.atom}.channel = {spec.channel}",
                    f"  {spec.atom}.canRead = {alloy_set(spec.can_read)}",
                    f"  {spec.atom}.canWrite = {alloy_set(spec.can_write)}",
                    f"  {spec.atom}.canExec = {alloy_set(spec.can_exec)}",
                    f"  {spec.atom}.anyMappings = {alloy_set(set(spec.any_mappings))}",
                    "",
                ]
            )

        for entry in deployment.any_entries:
            lines.extend(
                [
                    f"  {entry.atom}.count = {entry.count}",
                    f"  {entry.atom}.access = {entry.access}",
                    "",
                ]
            )

        for transition in transitions:
            lines.extend(
                [
                    f"  {transition.atom}.owner = {transition.owner}",
                    f"  {transition.atom}.transitionType = {transition.transition_type}",
                    f"  {transition.atom}.range = {alloy_set(transition.ids)}",
                    f"  {transition.atom}.action = {transition.action}",
                    "",
                ]
            )

        lines.extend(
            [
                "}",
                "",
                "pred validConfiguration {",
                "  configuration",
                "  valid",
                "}",
                "",
                "assert ConfigurationIsValid {",
                "  configuration implies valid",
                "}",
                "",
            ]
        )

        largest = max(
            5,
            len(deployment.peers),
            len(deployment.channels),
            len(deployment.policies),
            len(specs),
            len(deployment.any_entries),
            len(transitions),
            len(deployment.transition_ids),
        )
        max_count = max(
            [entry.count for entry in deployment.any_entries if entry.count > 0]
            + [largest]
        )
        bitwidth = max(4, max_count.bit_length() + 1)
        scope = f"for {largest} but {bitwidth} Int"
        lines.extend(
            [
                f"run configuration {scope}",
                f"run validConfiguration {scope}",
                f"check ConfigurationIsValid {scope}",
                "",
            ]
        )
        return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compile Mica JSON policy files into an Alloy module"
    )
    parser.add_argument("policies", nargs="+", type=Path)
    parser.add_argument("-o", "--output", required=True, type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--module", default="generated/configuration")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        compiler = Compiler(Aliases.load(args.manifest))
        for policy in args.policies:
            compiler.compile_file(policy)
        output = compiler.emit(args.module)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output)
    except CompileError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
