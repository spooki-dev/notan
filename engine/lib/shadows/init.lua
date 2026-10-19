local Path = (...):gsub("%.", "/")
local Shadows = {}

package.loaded["shadows"] = Shadows
-- The submodules were rewritten to require this module by its vendored path
-- ("engine.lib.shadows"); register it under that name too before loading them,
-- or the first require of the library fails with a module loop.
package.loaded[(...)] = Shadows
package.preload["shadows.Object"]			=	assert(love.filesystem.load(Path.."/Object.lua"))
package.preload["shadows.Transform"]		=	assert(love.filesystem.load(Path.."/Transform.lua"))
package.preload["shadows.LightWorld"]		=	assert(love.filesystem.load(Path.."/LightWorld.lua"))
package.preload["shadows.Light"]				=	assert(love.filesystem.load(Path.."/Light.lua"))
package.preload["shadows.Star"]				=	assert(love.filesystem.load(Path.."/Star.lua"))
package.preload["shadows.Body"]				=	assert(love.filesystem.load(Path.."/Body.lua"))
package.preload["shadows.OutputShadow"]	=	assert(love.filesystem.load(Path.."/OutputShadow.lua"))
package.preload["shadows.PriorityQueue"]	=	assert(love.filesystem.load(Path.."/PriorityQueue.lua"))

-- Shadow shapes

package.preload["shadows.ShadowShapes.Shadow"]			=	assert(love.filesystem.load(Path.."/ShadowShapes/Shadow.lua"))
package.preload["shadows.ShadowShapes.CircleShadow"]	=	assert(love.filesystem.load(Path.."/ShadowShapes/CircleShadow.lua"))
package.preload["shadows.ShadowShapes.HeightShadow"]	=	assert(love.filesystem.load(Path.."/ShadowShapes/HeightShadow.lua"))
package.preload["shadows.ShadowShapes.ImageShadow"]	=	assert(love.filesystem.load(Path.."/ShadowShapes/ImageShadow.lua"))
package.preload["shadows.ShadowShapes.NormalShadow"]	=	assert(love.filesystem.load(Path.."/ShadowShapes/NormalShadow.lua"))
package.preload["shadows.ShadowShapes.PolygonShadow"]	=	assert(love.filesystem.load(Path.."/ShadowShapes/PolygonShadow.lua"))

-- Rooms. Room.lua sits beside Room/ rather than inside it (upstream has it at
-- Room/Room.lua) because the subclasses were rewritten to pull it in with
-- `require("engine.lib.shadows.Room")`, and that name has to resolve to a file.

package.preload["shadows.Room"]						=		assert(love.filesystem.load(Path.."/Room.lua"))
package.preload["shadows.Room.CircleRoom"]		=		assert(love.filesystem.load(Path.."/Room/CircleRoom.lua"))
package.preload["shadows.Room.PolygonRoom"]		=		assert(love.filesystem.load(Path.."/Room/PolygonRoom.lua"))
package.preload["shadows.Room.RectangleRoom"]	=		assert(love.filesystem.load(Path.."/Room/RectangleRoom.lua"))

package.preload["shadows.Functions"]				=		assert(love.filesystem.load(Path.."/Functions.lua"))
package.preload["shadows.Shaders"]					=		assert(love.filesystem.load(Path.."/Shaders.lua"))

require("engine.lib.shadows.Shaders")
require("engine.lib.shadows.Functions")

return Shadows