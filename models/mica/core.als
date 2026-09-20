module models/mica/core

sig Peer {}

sig Gateway in Peer {}

one sig Host {}

abstract sig MemType {}
one sig Protected, Unprotected extends MemType {}

-- A transition channel governs a class of control-flow transitions from a
-- peer to the untrusted host.
abstract sig TransitionType {}
one sig Call, Exception extends TransitionType {}

-- Platform-specific identifiers for individual calls or exceptions.
sig TransitionID {}

-- The action Mica applies when a covered transition occurs.
abstract sig TransitionAction {}
one sig Allow, Scrub, Block extends TransitionAction {}

sig TransitionChannel {
  owner: one Peer,
  transitionType: one TransitionType,
  -- This is probably not necessary. I could remove if it increases
  -- the model checking time too much
  range: some TransitionID,
  action: one TransitionAction
}

sig MemChannel {
  -- The memory type is intrinsic to the underlying shared resource.
  -- Other systems check that all peers map a channel with the same visibility
  memType: one MemType
}

abstract sig MemAccessRight {}
one sig ReadAccess, WriteAccess, ExecAccess extends MemAccessRight {}

-- A policy's ANY entry for a memory channel.
sig AnyMapping {
  count: one Int,
  access: one MemAccessRight
}

-- One policy's local description of an underlying memory channel.
sig MemChannelSpec {
  channel: one MemChannel,
  canRead: set Peer,
  canWrite: set Peer,
  canExec: set Peer,
  anyMappings: set AnyMapping
}

sig Policy {
  -- Peers named by this policy.
  peers: set Peer,

  -- Named peers whose complete channel access must be described here.
  strictPeers: set Peer,

  -- Policy-local descriptions of memory channels.
  memChannels: set MemChannelSpec,

  -- Control-flow transition channels described by this policy.
  -- FIXME: We need some facts about those as well!
  transitions: set TransitionChannel
}
