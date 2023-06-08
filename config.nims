# switch("d", "release")
switch("d", "ssl")
switch("d", "useMalloc")
switch("d", "nimTlsSize=1048576") # increase Thread Local Storage size to fix compilation error
# switch("debuginfo", "on")
switch("threads", "on")
switch("gc", "orc")
switch("path", "src")
switch("outdir", "bin")
