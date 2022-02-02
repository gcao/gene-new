import strutils

import libfswatch, libfswatch/fswatch

import ../types

# See https://nim-lang.org/docs/channels_builtin.html

type
  MonitorWrapperInternal = object
    monitor*: Monitor
    paths*: seq[string]

  MonitorWrapper* = ptr MonitorWrapperInternal

var monitor_thread: Thread[void]
var wrapper: MonitorWrapper = create(MonitorWrapperInternal, sizeof(MonitorWrapperInternal))
wrapper.monitor = new_monitor()
wrapper.paths = @[]

proc eval_reload(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  if frame.ns.module != nil:
    frame.ns.module.reloadable = true
    wrapper.paths.add(frame.ns.module.name & ".gene")

proc translate_reload(value: Value): Expr =
  Expr(
    evaluator: eval_reload,
  )

proc thread_callback() {.thread gcsafe.} =
  proc callback(event: fsw_cevent, event_num: cuint) =
    echo "FSWatch callback: path = " & $event.path
    HotReloadListener.send($event.path)

  for path in wrapper.paths:
    echo "Path to monitor: " & path
    wrapper.monitor.add_path(path)
  wrapper.monitor.set_callback(callback)
  wrapper.monitor.start()

proc monitor_is_running(): bool =
  wrapper.monitor.handle.fsw_is_running()

proc eval_start_monitor(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  if monitor_is_running():
    echo "The module monitor is running already. Skip starting."
    return false
  else:
    create_thread(monitor_thread, thread_callback)
    echo "The module module monitor has started."
    return true

proc translate_start_monitor(value: Value): Expr =
  Expr(
    evaluator: eval_start_monitor,
  )

proc eval_stop_monitor(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  try:
    if monitor_is_running():
      discard wrapper.monitor.handle.fsw_stop_monitor()
      echo "The module monitor has stopped."
      return true
    else:
      echo "The module monitor was not running. Nothing to stop."
      return false
  except CatchableError as e:
    echo e.msg
    echo e.get_stack_trace()

proc translate_stop_monitor(value: Value): Expr =
  Expr(
    evaluator: eval_stop_monitor,
  )

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["$set_reloadable"] = new_gene_processor(translate_reload)
    self.app.ns["$start_monitor"] = new_gene_processor(translate_start_monitor)
    self.app.ns["$stop_monitor"] = new_gene_processor(translate_stop_monitor)
