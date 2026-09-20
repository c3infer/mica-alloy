module examples/pipelines

open models/mica/core
open models/mica/relations
open models/mica/model

-- A three-peer pipeline connected only through protected memory:
--
--   a --write/read--> b --write/read--> c
--
-- The two protected channels permit information to flow from a to c without
-- making any peer a gateway or creating a path from a to the untrusted host.
pred protectedPipelineExample {
  #Peer = 3
  #MemChannel = 2

  some disj a, b, c: Peer, ab, bc: MemChannel {
    ab.memType = Protected
    channelMapped[ab] = a + b
    channelCanWrite[ab] = a
    channelCanRead[ab] = b

    bc.memType = Protected
    channelMapped[bc] = b + c
    channelCanWrite[bc] = b
    channelCanRead[bc] = c

    no Gateway
    Host not in a.^memoryFlow
    c in a.^memoryFlow
  }
}

-- A two-peer pipeline in which a dedicated gateway mediates host egress:
--
--   source --protected--> gatewayPeer --unprotected--> Host
--
-- The source writes to a protected internal channel, the gateway reads it,
-- and then the gateway writes to an unprotected channel visible to the host.
pred gatewayMemoryExample {
  #Peer = 2

  some disj source, gatewayPeer: Peer, internal, egress: MemChannel {
    internal.memType = Protected
    channelMapped[internal] = source + gatewayPeer
    channelCanWrite[internal] = source
    channelCanRead[internal] = gatewayPeer

    egress.memType = Unprotected
    channelMapped[egress] = gatewayPeer
    channelCanWrite[egress] = gatewayPeer

    Host in source.^memoryFlow
  }
}

run protectedPipelineExample for 5
run gatewayMemoryExample for 5
