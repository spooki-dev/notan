function love.conf(t)
  t.window.title = "Notan"
  -- Pins the save directory name so saves are shared between source runs and fused builds.
  t.identity = "notan"
  t.window.width = 1280
  t.window.height = 720
  t.window.resizable = true
  -- Small enough for a phone held upright. love.js sizes its canvas from the
  -- frame the page gives it but never below this, so a desktop-sized minimum
  -- would force a 1024px canvas onto a 414px screen and leave the browser to
  -- scale the whole app down to 40%. The control panel floats over the image
  -- rather than taking a column once the window is this narrow.
  t.window.minwidth = 320
  t.window.minheight = 320
  t.window.vsync = 1
  t.window.msaa = 0
end
