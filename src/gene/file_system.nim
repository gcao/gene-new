# Unify physical file system and virtual file system (e.g. archive file, inlined dir/file etc)

# Virtual Machind holds a reference to current working directory (cwd) which can be a virtual
# or physical dir.
# Every file's path contains a full path or a relaive path and a parent.
# When a path starts with "." or "..", translation of the new path starts from the file's dir.
# When a path starts with "/", new path starts from root of the physical file system.
# Otherwise, new path starts from CWD.

# Module search follows a slightly different approach. CWD refers to a collection of module
# load paths.
