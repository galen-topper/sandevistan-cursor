import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let configLoader = ConfigLoader()
print("Sandevistan: loaded config — ghostCount=\(configLoader.config.ghostCount), lifespan=\(configLoader.config.lifespanMs)ms")

app.run()
