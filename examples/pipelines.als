module examples/pipelines

open models/mica/core
open models/mica/relations
open models/mica/model

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
