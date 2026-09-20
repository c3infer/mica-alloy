module models/mica/relations

open models/mica/core

fun channelSpecs[ch: MemChannel]: set MemChannelSpec {
  ch.~channel
}

fun specMapped[spec: MemChannelSpec]: set Peer {
  spec.canRead + spec.canWrite + spec.canExec
}

fun channelMapped[ch: MemChannel]: set Peer {
  let specs = channelSpecs[ch] |
    specs.canRead + specs.canWrite + specs.canExec
}

fun channelCanRead[ch: MemChannel]: set Peer {
  channelSpecs[ch].canRead
}

fun channelCanWrite[ch: MemChannel]: set Peer {
  channelSpecs[ch].canWrite
}

fun channelCanExec[ch: MemChannel]: set Peer {
  channelSpecs[ch].canExec
}

fun accessRights[ch: MemChannel, peer: Peer]: set MemAccessRight {
  { right: MemAccessRight |
    (right = ReadAccess and peer in channelCanRead[ch]) or
    (right = WriteAccess and peer in channelCanWrite[ch]) or
    (right = ExecAccess and peer in channelCanExec[ch])
  }
}

-- Finds the unnamed peers using a particular access right on a channel
fun anyUsers[
  policy: Policy,
  spec: MemChannelSpec,
  right: MemAccessRight
]: set Peer {
  { peer: channelMapped[spec.channel] - policy.peers |
    right in accessRights[spec.channel, peer]
  }
}

pred permits[p: Policy, ch: MemChannel, peer: Peer] {
  some spec: p.memChannels {
    spec.channel = ch

    peer in specMapped[spec] or {
      peer in channelMapped[ch] - p.peers
      some accessRights[ch, peer]
      accessRights[ch, peer] in spec.anyMappings.access
    }
  }
}

fun memoryFlow: Peer -> (Peer + Host) {
  { src, dst: Peer |
    some ch: MemChannel |
      src in channelCanWrite[ch] and
      dst in channelCanRead[ch] and
      src + dst in channelMapped[ch]
  }
  +
  { src: Peer, h: Host |
    some ch: MemChannel |
      ch.memType = Unprotected and
      src in channelCanWrite[ch] and
      src in channelMapped[ch]
  }
}

fun peerFlow: Peer -> Peer {
  memoryFlow :> Peer
}
