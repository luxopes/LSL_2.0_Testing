use "events"
use "window"

class Application:
    function __init__():
        self.windows = []
        self.running = false
    end

    function run():
        self.running = true
        while self.running:
            evt = event_poll()
            if evt != null:
                self.handle_event(evt)
            end
            self.update()
            self.render()
            wait 16
        end
    end

    function quit():
        self.running = false
    end

    function handle_event(evt):
        wm_handle_event(evt)
        event_dispatch(evt)
    end

    function update():
        return null
    end

    function render():
        wm_composite()
    end
end
