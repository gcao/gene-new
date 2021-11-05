import libfswatch
import libfswatch/fswatch

import ../types
# import ./module

type
  MonitorWrapper* = ref object
    monitor*: Monitor

var paths: seq[string] = @[]
var wrapper: MonitorWrapper

proc eval_reload(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  if frame.ns.module != nil:
    frame.ns.module.reloadable = true
    paths.add(frame.ns.module.name & ".gene")

proc translate_reload(value: Value): Expr =
  Expr(
    evaluator: eval_reload,
  )

proc eval_start_monitor(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  if paths.len == 0:
    echo "No path to monitor. Skip starting monitor"
    return false
  else:
    proc callback(event: fsw_cevent, event_num: cuint) =
      echo "FWS callback: path = " & $event.path

    wrapper = MonitorWrapper(monitor: new_monitor())
    for path in paths:
      wrapper.monitor.add_path(path)
    wrapper.monitor.set_callback(callback)
    wrapper.monitor.start()
    echo "The module monitor has started."
    return true

proc eval_stop_monitor(self: VirtualMachine, frame: Frame, target: Value, expr: var Expr): Value =
  try:
    if wrapper == nil or not wrapper.monitor.handle.fsw_is_running():
      echo "The module monitor was not running. Nothing to stop."
      return false
    else:
      discard wrapper.monitor.handle.fsw_stop_monitor()
      echo "The module monitor has stopped."
  except CatchableError as e:
    echo e.msg
    echo e.get_stack_trace()

proc translate_start_monitor(value: Value): Expr =
  Expr(
    evaluator: eval_start_monitor,
  )

proc translate_stop_monitor(value: Value): Expr =
  Expr(
    evaluator: eval_stop_monitor,
  )

proc init*() =
  VmCreatedCallbacks.add proc(self: VirtualMachine) =
    self.app.ns["$set_reloadable"] = new_gene_processor(translate_reload)
    self.app.ns["$start_monitor"] = new_gene_processor(translate_start_monitor)
    self.app.ns["$stop_monitor"] = new_gene_processor(translate_stop_monitor)