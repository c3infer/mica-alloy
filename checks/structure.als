module checks/structure

open models/mica/core
open models/mica/model

assert AtMostOneSpecPerPolicyAndChannel {
  all policy: Policy, ch: MemChannel |
    lone { spec: policy.memChannels | spec.channel = ch }
}

check AtMostOneSpecPerPolicyAndChannel for 5
