import os

import gene/types

import ./helpers

# Keywords:
# nil
# true/false
# discard: discard the result of an expression (borrowed from Nim) - should we use dump instead?
# noop: (noop) do nothing and return nil
# var, let, const
# if, elif, else
# and, or, xor, not
# for, in: loop over a collection
# while, until: loop while/until a condition is true
# repeat: loop x times
# loop: loop forever
# break, continue
# case, when, else
# enum
# range ??
# do
# scoped ??: create a new scope and run the code in it
# try, throw, catch, finally, retry (go back to the start of the try block)
# ns
# class, new, super, object
# self
# is: (a is A) => (is a A)
# mixin: (mixin M) (class C (.mixin M))
# cast
# fn, fnx, fnxx, macro
# return
# import, export, include
# match
# print, println ??
# assert ??
# async, await: should start as a library and make its way into the language until it's stable
# spawn ??: spawn a new thread, should start as a library and make its way into the language until it's stable
# exit

# Operators or symbols with special meaning:
# _
# : quote
# % unquote # maybe change this to #%
# = == != === !== += -= *= /= %= **= <<= >>= &= |= ^= ~=
# ->, =>: used for defining blocks
# + - * / % ** << >> & | ^ ~ ...
# @ @*

# Special variables:
# $vm: the current VM instance, can be used to access the VM's version, flags etc
# $app
# $pkg
# $module
# $ns
# $args
# $class: skip because this should be accessible as self/.class
# $caller: the caller function/macro/block/method
# $callee: the current function/macro/block/method
# $dir $file $line
# $full_cmd $cmd $cmd_args
# $main_file $main_dir: the main file/directory of the current program
# $cwd
# $user
# $home
# $ex
# $result
# $thread

# For any $x not mentioned above, $x = gene/x
# So it's important to define the $x variables in the gene namespace to avoid conflicts
# For example, $sleep = gene/sleep

# Or maybe we can do this:

# $$x = gene/x: the cons of this is that it's not very readable, e.g. ($$print ...) vs (print ...)


# test_interpreter """
#   $home
# """, get_env("HOME")
