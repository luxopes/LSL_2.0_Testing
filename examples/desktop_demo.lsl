use "hardware"
use "window"
use "widgets"
use "app"
use "events"

function demo_button_clicked(widget):
    print "Button clicked!"
end

class DemoApp:
    function __init__():
        Application__init__(self)
        wm_init(800, 600)
        self.main_window = wm_create_window(100, 80, 400, 300, "Hello LSL Desktop")
        self.button = new Button("Click Me!")
        self.button.x = 120
        self.button.y = 80
        self.button.width = 140
        self.button.height = 40
        self.button.on_click = "demo_button_clicked"
        wm_add_widget(self.main_window, self.button)
        self.label = new Label("Welcome to LSL GUI")
        self.label.x = 120
        self.label.y = 30
        wm_add_widget(self.main_window, self.label)
        self.input = new TextInput()
        self.input.x = 120
        self.input.y = 140
        self.input.width = 200
        self.input.height = 30
        wm_add_widget(self.main_window, self.input)
    end

    function handle_event(evt):
        Application__handle_event(self, evt)
    end

    function update():
        return null
    end

    function render():
        wm_composite()
    end

    function run():
        Application__run(self)
    end
end

app = new DemoApp()
app.run()
