module models/mica/constraints

open models/mica/core
open models/mica/relations

pred policyShape {
  all policy: Policy {
    -- Strictness is a property assigned to a peer named by this policy.
    policy.strictPeers in policy.peers

    -- Memory channel specifications can only map peers named by the policy.
    all spec: policy.memChannels |
      specMapped[spec] in policy.peers
  }
}

pred noOrphans {
  -- Every modeled object is affiliated with at least one policy.
  Peer = Policy.peers
  MemChannel = Policy.memChannels.channel
  TransitionChannel = Policy.transitions
  MemChannelSpec = Policy.memChannels
  AnyMapping = Policy.memChannels.anyMappings
}

pred strictPeersHaveNoUnlistedChannels {
  -- Every channel accessible to a strict peer must be described by the policy
  -- that marks the peer strict.
  all policy: Policy, peer: policy.strictPeers, ch: MemChannel |
    peer in channelMapped[ch] implies
      some spec: policy.memChannels | spec.channel = ch
}

pred memorySpecificationShape {
  -- Every MemChannelSpec belongs to exactly one policy
  all spec: MemChannelSpec |
    one policy: Policy | spec in policy.memChannels

  -- A policy has at most one specification for each memory channel
  all policy: Policy, ch: MemChannel |
    lone { spec: policy.memChannels | spec.channel = ch }

  -- AnyMapping belongs to exactly one MemChannelSpec
  all mapping: AnyMapping |
    one spec: MemChannelSpec | mapping in spec.anyMappings

  -- Any two distinct AnyMapping objects must cover different access rights
  all spec: MemChannelSpec, disj left, right: spec.anyMappings |
    left.access != right.access
}

pred anyMappingCountShape {
  -- -1 means unlimited; every other valid count is positive.
  all mapping: AnyMapping |
    mapping.count = -1 or mapping.count > 0
}

pred anyMappingsCoverUnnamedPeers {
  all policy: Policy, spec: policy.memChannels {
    -- Named runtime participants must be described explicitly. The remaining
    -- runtime participants consume ANY entries.
    specMapped[spec] = channelMapped[spec.channel] & policy.peers

    all peer: channelMapped[spec.channel] - policy.peers {
      some accessRights[spec.channel, peer]
      accessRights[spec.channel, peer] in spec.anyMappings.access
    }
  }
}

pred anyMappingCounts {
  -- A bounded ANY entry cannot be consumed by more peers than its count.
  all policy: Policy,
      spec: policy.memChannels,
      mapping: spec.anyMappings |
    mapping.count = -1 or
      #anyUsers[policy, spec, mapping.access] <= mapping.count
}

pred gatewayMatchesUnprotectedMemory {
  -- A peer is a gateway exactly when it maps unprotected memory.
  all peer: Peer |
    peer in Gateway iff some ch: MemChannel |
      ch.memType = Unprotected and peer in channelMapped[ch]
}

pred valid {
  -- The complete set of constraints for a valid Mica configuration.
  policyShape
  noOrphans
  strictPeersHaveNoUnlistedChannels
  memorySpecificationShape
  anyMappingCountShape
  anyMappingsCoverUnnamedPeers
  anyMappingCounts
  gatewayMatchesUnprotectedMemory
}
