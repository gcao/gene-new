# "0123456789".abbrev(6) => "012...789"
# "0123456789".abbrev(20) => "0123456789"
proc abbrev*(s: string, len: int): string =
  if len >= s.len:
    return s
  else:
    s[0..int((len+1)/2)] & "..." & s[s.len - int(len/2)..^1]

# template dbg*(args: untyped) =
#   echo instantiation_info() & $args
