module checks/confidentiality

open models/mica/core
open models/mica/relations
open models/mica/model

assert HostReachabilityRequiresGatewayOnPath {
  all src: Peer |
    Host in src.^memoryFlow implies
      some (src.*peerFlow & Gateway)
}

assert ProtectedChannelsDoNotFlowDirectlyToHost {
  all peer: Peer |
    Host in peer.memoryFlow implies
      some ch: MemChannel |
        ch.memType = Unprotected and
        peer in channelCanWrite[ch]
}

check HostReachabilityRequiresGatewayOnPath for 5
check ProtectedChannelsDoNotFlowDirectlyToHost for 5
