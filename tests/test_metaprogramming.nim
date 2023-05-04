# import unittest

# import gene/types

# import ./helpers

# Metaprogramming ideas:

# Namespace
# * define member with hard-coded name, or name from expression
# * members: will return members defined explicitly, not those defined by on_member_missing callbacks
# * on_member_defined (called when a member is defined or re-defined)
# * remove_member
# * on_member_removed
# v on_member_missing (invoked only if <some_ns>/something is invoked and something is not defined)
# * has_member - should it be consistent with on_member_missing?
#                so it will call all on_member_missing callbacks if necessary?
#                OR it'll work similar to members.contains(name)?

# Class
# * define methods with hard-coded name, or name from expression
# * define methods with native implementation
# * methods: will return methods defined explicitly or inherited from parent classes or mixins
#            but not those responded by on_method_missing callbacks
# * on_method_defined (called when a method is defined or re-defined)
# * remove_method
# * on_method_removed
# * on_method_missing
# * has_method - should it be consistent with on_method_missing?

# v on_extended - can not be undone

# * on_new - called when an instance is created
#            should be called with the instance fully initialized(after `new` is called)?
#            Do we even need this? all logic can be added to (.ctor ...)

# Mixin
# * on_included - can not be undone

# Module
# * module on_imported

# Aspect
# * on_applied
# * on_disabled
# * on_enabled
# * ...
