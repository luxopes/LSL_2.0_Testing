use "hardware"

event_queue = []
event_handlers = []

function list_pop_front(items):
    if len(items) == 0:
        return [null, []]
    end
    out = []
    i = 1
    while i < len(items):
        out = out + [items[i]]
        i = i + 1
    end
    return [items[0], out]
end

function event_post(evt):
    event_queue = event_queue + [evt]
end

function event_on(event_type, handler_name):
    event_handlers = event_handlers + [[event_type, handler_name]]
end

function event_dispatch(evt):
    i = 0
    while i < len(event_handlers):
        handler = event_handlers[i]
        if handler[0] == evt["type"]:
            __lsl_call1(handler[1], evt)
        end
        i = i + 1
    end
end

function event_pump():
    key = kb_poll()
    if key != null and key != 0:
        event_post({type: "key", code: key})
    end
    mouse = mouse_state()
    if is_list(mouse) and len(mouse) >= 3:
        if mouse[0] != 0 or mouse[1] != 0 or mouse[2] != 0:
            event_post({type: "mouse", dx: mouse[0], dy: mouse[1], buttons: mouse[2]})
        end
    end
end

function event_poll():
    event_pump()
    if len(event_queue) > 0:
        res = list_pop_front(event_queue)
        event_queue = res[1]
        return res[0]
    end
    return null
end
