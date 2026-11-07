-- =====================================================================
--  N's 'tion - Liquid Glass engine v5.4
--  Targets the boatbomber Glassmorphic look with our own implementation,
--  material values mapped 1:1 from their public config:
--   Thickness 0.15 . Refraction 4.0 . Chromatic Aberration 1.0
--   Fresnel 0.1 size / 40 hardness / 25 intensity
--   Glare 0.2 size / 40 hardness / 70 intensity / 90 convergence / 50 opposite / -50deg
--   Blur 0.06-scale frost . Corner 24 . Superellipse 3
--  Interaction ports from alexkkork/liquid-glass-luau (Pro):
--   - spring physics (semi-implicit Euler, tension 170 / friction 26)
--   - elastic cursor pull + hover scale on interactive glass panes
--   - cursor-sheen hover glow, mouse-chasing rim gradients
--   - depth pass (top light / bottom shade), press overlay on window
--  v5.6 material upgrade:
--   - LOCAL painted backdrop frost (camera-sampled grid -> Luau box blur ->
--     EditableImage): blur exists ONLY behind our UI, at Frost=100 strength;
--     global BlurEffect is forced OFF - the world stays pixel-crisp
--   - hover shine sweeps: two gloss streaks slide in from the left and exit
--     right while hovered (repeating), replacing the static glare beams
--  Foundation:
--   - LIGHT frosted glass by default; dark appearance is a settings toggle
--   - refraction band arcs + fresnel inner ring at the edge
--   - chromatic aberration split hairlines on the window rim only
--   - inset glare beams (no rounded-corner spill)
--   - rounded layered drop shadow (no square corners), synced to motion
--   - whole-window dragging (button-aware hit test), floating traffic lights
--   - profile card opens a SETTINGS content page like a normal button
--   - always-on-top watchdog (max DisplayOrder, re-asserted)
--  Module shape: loadstring(src)() -> UI ; UI.init() ; UI.kill()
-- =====================================================================

local UI = { Name = "GUI/UI" }
print("[N's 'tion] chunk loaded")

UI.Config = {
  Title     = "N's 'tion",
  StartSize = Vector2.new(700, 460),
  StartPos  = Vector2.new(190, 112),
  MinSize   = Vector2.new(540, 360),
  StartMode = "glass",
  StartTheme = "light",                -- light frost by default; dark is opt-in
  Glass = {
    -- names mirror the target's config for easy 1:1 tuning --
    Radius         = 24,     -- Corner Radius (offset 24)
    Superellipse   = 3.0,    -- look reference (Roblox has no SDF; UICorner approximates)
    Thickness      = 22,     -- 0.15 scale ~ 22px on the target's 150px widget
    Refraction     = 4.00,   -- refraction factor (band arc strength)
    Aberration     = 1.00,   -- chromatic aberration (rim RGB split)
    FresnelInner   = 15,     -- 0.1 scale ~ 15px on the target's widget
    FresnelIntensity = 25,
    FresnelHardness  = 40,
    GlareSize      = 36,     -- 0.2 scale ~ 30px on the target's widget (px band)
    GlareIntensity = 70,
    GlareHardness  = 40,
    GlareConvergence = 90,
    GlareOpposite  = 50,
    GlareAngle     = -50,
    GlareFollow    = 8,      -- mouse parallax px
    Blur           = 26,     -- legacy: global BlurEffect is now forced 0 (see THEMES.blurb);
    LineFx         = false,  -- edge linework (refraction band rings, fresnel ring, rim
                             -- light, CA hairlines): FALSE = clean borderless glass
    Frost          = 100,    -- painted backdrop frost strength (0-100+): heavier = creamier.
                             -- True LOCALIZED blur only behind our UI - sampled via camera
                             -- raycasts, blurred in Luau, written to an EditableImage.
    SweepGap       = 1.7,    -- seconds between shine sweep repeats while hovered
    -- liquid-glass interaction ports (alexkkork/liquid-glass-luau Pro spec) --
    ElasticEnabled   = true,  -- spring "liquid" pull of interactive panes toward cursor
    ElasticIntensity = 6,     -- max pull px at the pane edge
    SpringTension    = 170,   -- Pro spring defaults (tension/friction, semi-implicit Euler)
    SpringFriction   = 26,
    HoverScale       = 1.02,  -- Pro default hover scale-up
    HoverGlowOpacity = 0.12,  -- radial cursor-sheen peak inside panes
    BorderFollow     = 30,    -- deg of rim-gradient rotation chase from cursor X
    PressOverlayOp   = 0.94,  -- press darkening as TRANSPARENCY (1 = nothing, 0.94 = whisper)
    TopGlowOp        = 0.10,  -- depth pass: light pooling at the top edge
    BottomShadeOp    = 0.13,  -- depth pass: shade pooling at the bottom edge
  },
}

function UI.init()
  if UI._gui then return end -- idempotent: loader already booted us
  print("[N's 'tion] UI.init() starting...")

local Players   = game:GetService("Players")
local TweenSvc  = game:GetService("TweenService")
local UIS       = game:GetService("UserInputService")
local Lighting  = game:GetService("Lighting")
local RunSvc    = game:GetService("RunService")
local AssetSvc  = game:GetService("AssetService")
local lp        = Players.LocalPlayer

if not lp then
  warn("[N's 'tion] LocalPlayer is nil - wait for player to load, then run UI.init() manually")
  return
end
print("[N's 'tion] LocalPlayer found: " .. tostring(lp.Name))

local cons = {}
local function bind(fn) cons[#cons+1] = fn end

local TI_Q   = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TI_UP  = TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_POP = TweenInfo.new(0.42, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
local TI_SM  = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_HOT = TweenInfo.new(0.10, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)
local TI_PRT = TweenInfo.new(0.07, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out)

local G = UI.Config.Glass

local GREEN    = Color3.fromRGB(48, 209, 88)
local RED      = Color3.fromRGB(255, 69, 58)
local YELLOW   = Color3.fromRGB(255, 214, 10)

local THEMES = {
  light = {
    blur     = 0,    -- GLOBAL blur FORCED OFF: the frost behind our window is painted
                     -- locally (camera-sampled EditableImage) so the world stays crisp
    glareMul = 1.0,
    winTint  = Color3.fromRGB(255, 255, 255), winT = 0.82, -- ~18% surface: visible glass
    sideTint = Color3.fromRGB(255, 255, 255), sideT = 0.75,
    pillTint = Color3.fromRGB(255, 255, 255), pillT = 0.65, pillHot = 0.50, pillSel = 0.32,
    profT = 0.60, profHot = 0.46,
    opqWin = Color3.fromRGB(243, 244, 248), opqSide = Color3.fromRGB(248, 249, 252),
    opqSideT = 0.05, opqPill = Color3.fromRGB(255, 255, 255),
    textHi = Color3.fromRGB(24, 27, 37), textDim = Color3.fromRGB(90, 96, 112),
    grip = Color3.fromRGB(122, 128, 144),
    switchOff = Color3.fromRGB(172, 174, 186),
    shadowT = 0.968,
    glow = Color3.fromRGB(255, 255, 255),      -- hover cursor sheen color
    depthTop = Color3.fromRGB(255, 255, 255),  -- depth pass colors
    depthBottom = Color3.fromRGB(20, 24, 34),
    depthTopT = 1 - 0.10, depthBottomT = 1 - 0.13,
  },
  dark = {
    blur     = 0,
    glareMul = 0.60,
    winTint  = Color3.fromRGB(18, 20, 26), winT = 0.55,
    sideTint = Color3.fromRGB(24, 26, 34), sideT = 0.35,
    pillTint = Color3.fromRGB(48, 50, 60), pillT = 0.28, pillHot = 0.19, pillSel = 0.14,
    profT = 0.24, profHot = 0.16,
    opqWin = Color3.fromRGB(52, 52, 58), opqSide = Color3.fromRGB(34, 34, 40),
    opqSideT = 0.06, opqPill = Color3.fromRGB(66, 66, 74),
    textHi = Color3.fromRGB(248, 249, 252), textDim = Color3.fromRGB(206, 212, 226),
    grip = Color3.fromRGB(206, 212, 226),
    switchOff = Color3.fromRGB(122, 122, 132),
    shadowT = 0.955,
    glow = Color3.fromRGB(180, 200, 255),
    depthTop = Color3.fromRGB(255, 255, 255),
    depthBottom = Color3.fromRGB(0, 0, 0),
    depthTopT = 1 - 0.12, depthBottomT = 1 - 0.13,
  },
}
local THEME = THEMES[UI.Config.StartTheme] or THEMES.light

local ICONS = {                      -- Lucide decal pack (Footagesus/Icons, MIT)
  x        = "rbxassetid://110786993356448",
  minus    = "rbxassetid://118026365011536",
  maximize = "rbxassetid://76045941763188",
  clock    = "rbxassetid://121808839832144",
  settings = "rbxassetid://80758916183665",
  sliders  = "rbxassetid://85538382643347",
  moon     = "rbxassetid://83380517901735",
}

local S = {
  mode = UI.Config.StartMode,
  dark = (UI.Config.StartTheme == "dark"),
  minimized = false, full = false,
  winSize = UI.Config.StartSize,
  winPos  = UI.Config.StartPos,
  minSize = UI.Config.MinSize,
  saved = nil, savedFull = nil,
  sel = 0, -- 0 = no category, 1/2 = coming soon pages
}

-- ============================================== cleanup / root
local pg = lp:FindFirstChild("PlayerGui")
local old = pg and pg:FindFirstChild("__AppleHub"); if old then old:Destroy() end
for _, b in ipairs(Lighting:GetChildren()) do
  if b:IsA("BlurEffect") and b.Name == "__HubBlur" then b:Destroy() end
end

local gui = Instance.new("ScreenGui")
gui.Name = "__AppleHub"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 2147483647 -- always on top of every other PlayerGui layer (2^31-1, property max)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.Parent = lp:WaitForChild("PlayerGui")
  UI._gui = gui
  print("[N's 'tion] ScreenGui parented to PlayerGui")

  -- NO GLOBAL BLUR: the localized "painted frost" system below handles blur
  -- ONLY behind our UI via an EditableImage inside the window pane.
  -- The world outside stays pixel-crisp.

  -- ============================================== helpers
local function tw(o, ti, props) local t = TweenSvc:Create(o, ti, props); t:Play(); return t end

-- themed text: every TextLabel is registered so applyTheme() can recolor live
local textRefs = {}
local function txt(parent, str, size, font, role, transp)
  local t = Instance.new("TextLabel")
  t.BackgroundTransparency = 1
  t.Font = font or Enum.Font.GothamMedium
  t.TextSize = size or 14
  t.TextColor3 = (role == "dim") and THEME.textDim or THEME.textHi
  t.TextTransparency = transp or 0
  t.Text = str
  t.Parent = parent
  textRefs[#textRefs + 1] = { o = t, r = role }
  return t
end

local function corner(o, r)
  local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c
end

local function stroke(o, th, transp, colr)
  local s = Instance.new("UIStroke")
  s.Thickness = th or 1; s.Transparency = transp or 0.6
  s.Color = colr or Color3.new(1,1,1)
  s.Parent = o; return s
end

-- themed icon: registered like txt; iconFx keeps a fixed tint (traffic glyphs)
local iconRefs = {}
local function icon(parent, id, px, role, transp)
  local im = Instance.new("ImageLabel")
  im.BackgroundTransparency = 1
  im.Size = UDim2.fromOffset(px, px)
  im.Image = id
  im.ImageColor3 = (role == "dim") and THEME.textDim or THEME.textHi
  im.ImageTransparency = transp or 0
  im.Parent = parent
  iconRefs[#iconRefs + 1] = { o = im, r = role }
  return im
end
local function iconFx(parent, id, px, tint, transp)
  local im = Instance.new("ImageLabel")
  im.BackgroundTransparency = 1
  im.Size = UDim2.fromOffset(px, px)
  im.Image = id
  im.ImageColor3 = tint
  im.ImageTransparency = transp or 0
  im.Parent = parent
  return im
end

local function pressable(btn, ref, hit)
  hit = hit or btn
  hit.InputBegan:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
      tw(btn, TI_PRT, { Size = UDim2.new(ref.X.Scale, ref.X.Offset * 0.94, ref.Y.Scale, ref.Y.Offset * 0.94) })
    end
  end)
  hit.InputEnded:Connect(function(io)
    if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
      tw(btn, TI_UP, { Size = ref })
    end
  end)
end

local gripDots = {}
local function shapeGrip(parent)
  local holder = Instance.new("Frame")
  holder.Size = UDim2.fromOffset(12, 12)
  holder.BackgroundTransparency = 1
  holder.Parent = parent
  for r = 0, 2 do
    for c = 0, 2 do
      if c + r <= 2 then
        local d = Instance.new("Frame", holder)
        d.Size = UDim2.fromOffset(2.5, 2.5)
        d.Position = UDim2.new(0, c * 4.5, 0, r * 4.5)
        d.BackgroundColor3 = THEME.grip
        d.BackgroundTransparency = 0.35
        d.BorderSizePixel = 0
        corner(d, 2)
        gripDots[#gripDots + 1] = d
end
    end
    return holder
  end
end

-- ~~~~~~~~~~~~ glass material stack ~~~~~~~~~~~~
local rimSet    = {} -- CA hairline pairs (drift)
local glassFx   = {} -- glass-only material effects (band/fresnel/rim light): hidden in opaque

-- ============================================== liquid glass interaction (v5.4 port)
-- Spring physics + cursor-reactive layers, ported from the behavior spec of
-- alexkkork/liquid-glass-luau (Pro): semi-implicit Euler springs (tension 170 /
-- friction 26), elastic mouse-follow of interactive panes, cursor-sheen hover
-- glow, mouse-chasing rim gradients, hover/press scale - re-implemented on the
-- hub's own material stack so it obeys the glass/opaque theme matrix.

local springs = {}
local function springNew()
  local sp = {
    x = 0, y = 0, vx = 0, vy = 0, tx = 0, ty = 0, rest = true,
    k = math.max(1, G.SpringTension or 170),
    c = math.max(1, G.SpringFriction or 26),
  }
  springs[#springs + 1] = sp
  return sp
end
local function springTarget(sp, tx, ty)
  sp.tx, sp.ty = tx, ty
  if math.abs(tx - sp.x) > 0.01 or math.abs(ty - sp.y) > 0.01 then sp.rest = false end
end
local function springStep(sp, dt)
  if sp.rest then return end
  local h = 1 / 120
  while dt > 0 do
    local st = math.min(h, dt)
    dt = dt - st
    local ax = -sp.k * (sp.x - sp.tx) - sp.c * sp.vx
    local ay = -sp.k * (sp.y - sp.ty) - sp.c * sp.vy
    sp.vx = sp.vx + ax * st
    sp.vy = sp.vy + ay * st
    sp.x = sp.x + sp.vx * st
    sp.y = sp.y + sp.vy * st
  end
  if math.sqrt(sp.vx * sp.vx + sp.vy * sp.vy) < 0.01
    and math.abs(sp.x - sp.tx) < 0.01 and math.abs(sp.y - sp.ty) < 0.01 then
    sp.x, sp.y, sp.vx, sp.vy, sp.rest = sp.tx, sp.ty, 0, 0, true
  end
end

-- interactive glass elements: hover sheen / elastic pull / scale springs
local fxSet = {}
-- rim gradients that chase the cursor (window material lighting)
local rimFollow = {}
-- frame-based glass material passes (depth layer fills)
local glassFrames = {}
-- hover shine sweep streaks (slide in from left, exit right)
local sweepList = {}

local function springPane(pane, radius, opacity)
  pane.ClipsDescendants = true
  local sc = Instance.new("UIScale", pane)
  sc.Scale = 1
  local e = {
    pane = pane, scale = sc, hover = false,
    glowMax = opacity,
    base = nil, -- captured lazily on first drive (Position is set by callers)
    spring = springNew(),
    scaleSpr = springNew(),
  }
  -- scale spring starts at rest on 1
  e.scaleSpr.x, e.scaleSpr.tx = 1, 1
  if G.ElasticEnabled then
    e.elastic = G.ElasticIntensity or 6
  end
  fxSet[#fxSet + 1] = e
  return e
end

local function makeGlass(parent, radius, opts)
  opts = opts or {}
  local isWindow = opts.real and true or false
  local pane = Instance.new("Frame")
  pane.Name = opts.name or "GlassPane"
  pane.BackgroundColor3 = opts.tint or THEME.winTint
  pane.BackgroundTransparency = opts.baseT or THEME.winT
  pane.BorderSizePixel = 0
  pane.Parent = parent
  corner(pane, radius)

-- EDGE REFRACTION: 4 directional bands (Top/Bottom/Left/Right) with multiple
  -- overlapping layers - simulates light bending through thick glass edges.
  -- Each layer has a depth factor and position offset that increases toward the edge.
  if isWindow or opts.innerRing then
    local refraction = G.Refraction or 4.0
    local edgeWidth = math.max(6, G.Thickness or 22)
    local layers = math.clamp(math.floor(refraction), 2, 6)
    local falloff = 2

    local function refractionBand(side, layerIdx)
      local depthFactor = 1 - (layerIdx - 1) / layers
      local offsetAmount = refraction * math.pow(depthFactor, falloff)
      local band = Instance.new("Frame", pane)
      band.Name = "Refraction" .. side .. layerIdx
      if side == "Top" or side == "Bottom" then
        band.Size = UDim2.new(1, 0, 0, edgeWidth)
        if side == "Top" then
          band.Position = UDim2.new(0, 0, 0, -offsetAmount * layerIdx * 0.1)
          band.AnchorPoint = Vector2.new(0, 0)
        else
          band.Position = UDim2.new(0, 0, 1, offsetAmount * layerIdx * 0.1)
          band.AnchorPoint = Vector2.new(0, 1)
        end
      else
        band.Size = UDim2.new(0, edgeWidth, 1, 0)
        if side == "Left" then
          band.Position = UDim2.new(0, -offsetAmount * layerIdx * 0.1, 0, 0)
          band.AnchorPoint = Vector2.new(0, 0)
        else
          band.Position = UDim2.new(1, offsetAmount * layerIdx * 0.1, 0, 0)
          band.AnchorPoint = Vector2.new(1, 0)
        end
      end
      local edgeOpacity = 0.05 * depthFactor
      local dg = Instance.new("UIGradient", band)
      if side == "Top" or side == "Bottom" then
        dg.Rotation = side == "Top" and 90 or 270
      else
        dg.Rotation = side == "Left" and 180 or 0
      end
      dg.Color = ColorSequence.new(Color3.new(1, 1, 1))
      dg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1 - edgeOpacity),
        NumberSequenceKeypoint.new(0.5, 1),
        NumberSequenceKeypoint.new(1, 1),
      })
      glassFx[#glassFx + 1] = { o = band, base = 1 - edgeOpacity }
    end

    for _, side in ipairs({ "Top", "Bottom", "Left", "Right" }) do
      for i = 1, layers do
        refractionBand(side, i)
      end
    end
  end

  if isWindow then
    -- CHROMATIC ABERRATION: three overlapping edge frames tinted Red, Green, Blue,
    -- each slightly offset to create the rainbow edge effect.
    -- RedAdjusted = RGB(255,100,100), GreenAdjusted = RGB(100,255,100),
    -- BlueAdjusted = RGB(100,100,255) - tinted toward pure RGB for stronger effect.
    local abIntensity = G.Aberration or 1.0
    local redTint   = Color3.fromRGB(255, 100, 100)
    local greenTint = Color3.fromRGB(100, 255, 100)
    local blueTint  = Color3.fromRGB(100, 100, 255)

    local function makeChromaticChannel(tint, baseOffset, zIdx)
      local ch = Instance.new("Frame", pane)
      ch.Name = "Chromatic"
      ch.Size = UDim2.fromScale(1, 1)
      ch.Position = UDim2.fromOffset(baseOffset.X * abIntensity, baseOffset.Y * abIntensity)
      ch.AnchorPoint = Vector2.new(0, 0)
      ch.BackgroundTransparency = 1
      ch.BorderSizePixel = 0
      ch.ZIndex = zIdx
      corner(ch, radius)
      -- Edge-only transparency: visible only at edges (0-0.15 and 0.85-1)
      local edgeWidth = 0.15
      local edgeOpacity = 0.15
      local cg = Instance.new("UIGradient", ch)
      cg.Color = ColorSequence.new(Color3.new(1, 1, 1))
      cg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1 - edgeOpacity),
        NumberSequenceKeypoint.new(edgeWidth, 1),
        NumberSequenceKeypoint.new(1 - edgeWidth, 1),
        NumberSequenceKeypoint.new(1, 1 - edgeOpacity),
      })
      glassFx[#glassFx + 1] = { o = ch, base = 1 - edgeOpacity }
      return ch
    end

    local chRed   = makeChromaticChannel(redTint,   Vector2.new(-2, 0), 40)
    local chGreen = makeChromaticChannel(greenTint, Vector2.new(0, 0), 41)
    local chBlue  = makeChromaticChannel(blueTint,  Vector2.new(2, 0), 42)
    rimSet[#rimSet + 1] = { s1 = chRed, s2 = chGreen, s3 = chBlue }

    -- fresnel inner ring (FresnelInner / FresnelIntensity)
    local fres = Instance.new("Frame", pane)
    fres.Name = "Fresnel"
    fres.AnchorPoint = Vector2.new(0.5, 0.5)
    fres.Position = UDim2.fromScale(0.5, 0.5)
    fres.Size = UDim2.new(1, -(G.FresnelInner or 13) * 2, 1, -(G.FresnelInner or 13) * 2)
    fres.BackgroundColor3 = Color3.new(1,1,1)
    fres.BackgroundTransparency = 1
    fres.BorderSizePixel = 0
    corner(fres, math.max(2, radius - (G.FresnelInner or 13)))
    local fs = stroke(fres, 2.0, 1)
    local fg = Instance.new("UIGradient", fs)
    fg.Rotation = 225
    fg.Color = ColorSequence.new(Color3.new(1,1,1), Color3.fromRGB(170, 190, 230))
    local fpeak = 0.12 + 0.5 * ((G.FresnelIntensity or 25) / 100)
    fg.Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0.0, 1),
      NumberSequenceKeypoint.new(0.28, 1 - fpeak),
      NumberSequenceKeypoint.new(0.75, 1),
      NumberSequenceKeypoint.new(1, 1),
    })
    glassFx[#glassFx + 1] = { o = fs, base = 0 }

    -- glass rim light: thin white bevel - brightest top-left, vanishing bottom-right.
    -- Gradient-driven so it reads as material lighting, not a border outline.
    local hi = stroke(pane, 2.0, 1)
    local hg = Instance.new("UIGradient", hi)
    hg.Rotation = 225
    hg.Color = ColorSequence.new(Color3.new(1,1,1), Color3.new(1,1,1))
    hg.Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0.0, 0.40),
      NumberSequenceKeypoint.new(0.3, 0.62),
      NumberSequenceKeypoint.new(0.6, 0.85),
      NumberSequenceKeypoint.new(1.0, 0.94),
    })
    glassFx[#glassFx + 1] = { o = hi, base = 0 }

    -- hover shine sweeps: two light streaks that slide in from the LEFT and
    -- exit to the RIGHT while the window is hovered (repeats with a gap).
    -- Primary is the longer/fatter one (the streak that used to sit left);
    -- both are vertically centered so no end gets cut by the pane bottom.
    local sparks = {
      { len = 1.50, thick = math.max(24, G.GlareSize or 36),              delay = 0.00, dur = 1.05, peak = 0.50 },
      { len = 0.85, thick = math.max(14, (G.GlareSize or 36) * 0.6),      delay = 0.45, dur = 1.05, peak = 0.32 },
    }
    for _, sp in ipairs(sparks) do
      local b = Instance.new("Frame", pane)
      b.Name = "Sweep"
      b.AnchorPoint = Vector2.new(0.5, 0.5)
      b.Position = UDim2.new(-0.55, 0, 0.5, 0) -- parked off-left until driven
      b.Size = UDim2.new(sp.len, 0, 0, sp.thick)
      b.Rotation = G.GlareAngle or -50
      b.BackgroundColor3 = Color3.fromRGB(243, 246, 255)
      b.BackgroundTransparency = 1
      b.BorderSizePixel = 0
      b.Visible = false
      b.ZIndex = 0
      local sg = Instance.new("UIGradient", b)
      sg.Rotation = 90
      sg.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1))
      local pk = 1 - sp.peak
      sg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.28, pk + (1 - pk) * 0.55),
        NumberSequenceKeypoint.new(0.5, pk),
        NumberSequenceKeypoint.new(0.72, pk + (1 - pk) * 0.55),
        NumberSequenceKeypoint.new(1, 1),
      })
      sweepList[#sweepList + 1] = { f = b, def = sp }
    end
  end -- isWindow (material linework + sweeps)

  -- cursor-sheen hover glow + elastic pull/scale spring (interactive panes)
  if opts.interactive then
    local el = springPane(pane, radius, opts.glowMax or (G.HoverGlowOpacity or 0.12))
    if not opts.elastic then
      el.elastic = nil   -- glow reacts, pane never pulls (main window)
      el.noScale  = true -- a full window growing on hover feels wrong
    end
    local glow = Instance.new("Frame", pane)
    glow.Name = "HoverGlow"
    glow.Size = UDim2.fromScale(1, 1)
    glow.BackgroundColor3 = Color3.new(1, 1, 1)
    glow.BackgroundTransparency = 1
    glow.BorderSizePixel = 0
    glow.ZIndex = 0 -- material sheen lives under all pane content
    corner(glow, radius)
    local gg = Instance.new("UIGradient", glow)
    gg.Rotation = 45
    gg.Color = ColorSequence.new(THEME.glow)
    gg.Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 1),
      NumberSequenceKeypoint.new(0.5, 1 - el.glowMax),
      NumberSequenceKeypoint.new(1, 1),
    })
    el.glow, el.ggrad = glow, gg
  end

  if isWindow then
    -- depth pass: light pools at the top, shade at the bottom - makes the
    -- flat pane read as a translucent slab with thickness.
    local function depthPass(colr, fromTop, opacity)
      local f = Instance.new("Frame", pane)
      f.Name = fromTop and "DepthTop" or "DepthBottom"
      f.Size = UDim2.fromScale(1, 1)
      f.BackgroundColor3 = colr
      f.BackgroundTransparency = 1 - opacity
      f.BorderSizePixel = 0
      f.ZIndex = fromTop and 51 or 50
      corner(f, radius)
      local dg = Instance.new("UIGradient", f)
      dg.Rotation = fromTop and 90 or 270
      dg.Color = ColorSequence.new(colr, colr)
      dg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1 - opacity),
        NumberSequenceKeypoint.new(0.30, 1),
        NumberSequenceKeypoint.new(1, 1),
      })
      glassFrames[#glassFrames + 1] = { o = f, base = 1 - opacity }
      return f
    end
    depthPass(THEME.depthTop, true, G.TopGlowOp or 0.10)
    depthPass(THEME.depthBottom, false, G.BottomShadeOp or 0.13)

    -- INNER GLOW: subtle edge-only glow around inner edges of glass.
    -- Transparency: opaque at edges (0 and 1), fully transparent at 0.3 and 0.7.
    local ig = Instance.new("Frame", pane)
    ig.Name = "InnerGlow"
    ig.Size = UDim2.fromScale(1, 1)
    ig.BackgroundColor3 = THEME.depthTop
    ig.BackgroundTransparency = 1
    ig.BorderSizePixel = 0
    ig.ZIndex = 55
    corner(ig, radius)
    local igg = Instance.new("UIGradient", ig)
    igg.Color = ColorSequence.new(THEME.depthTop)
    igg.Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 1 - 0.05),
      NumberSequenceKeypoint.new(0.3, 1),
      NumberSequenceKeypoint.new(0.7, 1),
      NumberSequenceKeypoint.new(1, 1 - 0.05),
    })
    glassFrames[#glassFrames + 1] = { o = ig, base = 1 - 0.05 }

    -- secondary inner border: faint inset stroke for extra slab depth
    local inset = Instance.new("Frame", pane)
    inset.Name = "InnerBorder"
    inset.Size = UDim2.new(1, -4, 1, -4)
    inset.Position = UDim2.fromOffset(2, 2)
    inset.BackgroundTransparency = 1
    inset.BorderSizePixel = 0
    inset.ZIndex = 60
    corner(inset, math.max(2, radius - 2))

    -- press overlay: subtle darkening while the window is held
    local ov = Instance.new("Frame", pane)
    ov.Name = "PressOverlay"
    ov.Size = UDim2.fromScale(1, 1)
    ov.BackgroundColor3 = Color3.new(0, 0, 0)
    ov.BackgroundTransparency = 1
    ov.BorderSizePixel = 0
    ov.ZIndex = 5000
    corner(ov, radius)
    S.pressOv = ov

    -- rim gradients chase the cursor (Pro's mouse-responsive border reflection)
    -- Rotation formula: BaseRotation + mouseOffset.X * MouseInfluence * 30
    --                             + mouseOffset.Y * MouseInfluence * 10
    if fg then rimFollow[#rimFollow + 1] = { g = fg, base = 225, mul = 30 } end
    if hg then rimFollow[#rimFollow + 1] = { g = hg, base = 225, mul = 30 } end
  end

  return pane
end

-- ============================================== WINDOW
local win = makeGlass(gui, G.Radius, { name = "Window", real = true, interactive = true, glowMax = 0.08 })
win.Size = UDim2.fromOffset(S.winSize.X, S.winSize.Y)
win.Position = UDim2.fromOffset(S.winPos.X, S.winPos.Y)
win.ClipsDescendants = true
win.ZIndex = 1
S.win = win

-- rounded layered drop shadow: sibling of win (win clips, so it can't live inside),
-- synced to every size/position change so it never lags or squares off
local shadowRoot = Instance.new("Frame")
shadowRoot.Name = "Shadow"
shadowRoot.BackgroundTransparency = 1
shadowRoot.BorderSizePixel = 0
shadowRoot.Size = win.Size
shadowRoot.Position = win.Position
shadowRoot.ZIndex = 0
shadowRoot.Parent = gui
UI._shadowRoot = shadowRoot

local shadowLayers = {}
-- 10 feathered rings, 2px apart: reads as a gaussian halo - no per-layer hard edge
local SHADOW_PADS = { 2, 4, 6, 8, 10, 12, 14, 16, 18, 20 }
for i, pad in ipairs(SHADOW_PADS) do
  local l = Instance.new("Frame")
  l.Name = "L" .. i
  l.AnchorPoint = Vector2.new(0.5, 0.5)
  l.Position = UDim2.fromScale(0.5, 0.5)
  l.Size = UDim2.new(1, pad * 2, 1, pad * 2)
  l.BackgroundColor3 = Color3.new(0, 0, 0)
  l.BackgroundTransparency = THEME.shadowT
  l.BorderSizePixel = 0
  corner(l, G.Radius + pad)
  l.Parent = shadowRoot
  shadowLayers[#shadowLayers + 1] = l
end
local function syncShadow()
  shadowRoot.Position = win.Position
  shadowRoot.Size = win.Size
end
local function twWin(ti, props)
  tw(win, ti, props)
  tw(shadowRoot, ti, props) -- identical easing keeps them glued
end

-- ============================================== LOCAL BACKDROP FROST (v5.6)
-- BlurEffect only blurs the ENTIRE camera - "blur just behind the UI" doesn't
-- exist as a service. So we PAINT it: the world behind the window is
-- approximated on a coarse grid via camera raycasts (one color per cell, sky
-- fallback), blurred in Luau at G.Frost strength, and written into an
-- EditableImage that lives inside the window pane. Result: heavy frost ONLY
-- behind our UI, the world outside stays pixel-crisp. Refreshed continuously
-- on a ~2.5ms/frame raycast budget.
local frost = {
  gw = 12, gh = 9,
  res = Vector2.new(96, 64),
  refresh = 0.20,
  rowNext = 0,
  tLast = 0,
  ok = false,
  vis = {}, -- layers shown/hidden with material mode
}

do
  local layer = Instance.new("ImageLabel")
  layer.Name = "FrostPane"
  layer.Size = UDim2.fromScale(1, 1)
  layer.BackgroundTransparency = 1
  layer.ScaleType = Enum.ScaleType.Stretch
  layer.ZIndex = 20
  corner(layer, G.Radius)
  layer.Parent = win
  layer.Visible = false
  frost.vis[1] = layer
  frost.img = layer

  -- FROST NOISE LAYERS: multiple overlapping frames with seeded pseudo-random
  -- patterns at different rotations and scales - simulates the grain texture
  -- of real frosted glass (Pro technique).
  local noiseLayers = {}
  local noiseCount = math.clamp(math.floor((G.Frost or 100) / 30), 2, 5)
  local rotations = { 0, 45, 90, 135, 22.5, 67.5 }
  for i = 1, noiseCount do
    local nl = Instance.new("Frame", layer)
    nl.Name = "Noise" .. i
    nl.Size = UDim2.fromScale(1, 1)
    nl.BackgroundTransparency = 1
    nl.BorderSizePixel = 0
    nl.ZIndex = 25 + i
    corner(nl, G.Radius)
    nl.Rotation = rotations[(i - 1) % #rotations + 1]
    local ng = Instance.new("UIGradient", nl)
    ng.Rotation = 90
    -- Seeded pseudo-random noise: sin(seed*12.9898)*43758.5453 fractal part
    local stops = math.min(8, 4 + i)
    local colorKeys, transKeys = {}, {}
    for j = 0, stops do
      local seed = (G.Frost or 100) * 1000 + i * 100 + j * 100
      local noise = math.abs(math.sin(seed * 12.9898) * 43758.5453)
      noise = noise - math.floor(noise)
      local brightness = 0.95 + noise * 0.1
      colorKeys[#colorKeys + 1] = ColorSequenceKeypoint.new(j / stops, Color3.new(brightness, brightness, brightness))
      local noiseOpacity = math.clamp((1 - (G.NoiseOpacity or 0.08)) + noise * (G.NoiseOpacity or 0.08) * 0.5, 0.5, 1)
      transKeys[#transKeys + 1] = NumberSequenceKeypoint.new(j / stops, noiseOpacity)
    end
    ng.Color = ColorSequence.new(colorKeys)
    ng.Transparency = NumberSequence.new(transKeys)
    noiseLayers[#noiseLayers + 1] = nl
  end
  frost.noiseLayers = noiseLayers

  local okE, edi = pcall(function()
    return AssetSvc:CreateEditableImage(frost.res)
  end)
  if okE and edi then
    frost.edi = edi
    UI._frostEdi = edi
    local bound = false
    pcall(function() layer.Image = edi end)
    local iv
    pcall(function() iv = layer.Image end)
    if iv == nil or (type(iv) == "string" and #iv == 0) then
      pcall(function() layer.Image = (Content.fromObject and Content.fromObject(edi)) end)
      pcall(function() iv = layer.Image end)
    end
    if type(iv) == "userdata" or (type(iv) == "string" and #iv > 0) then bound = true end
    frost.ok = bound
  end
  if not frost.ok then
    -- fallback: pixel-cell frost so the effect exists even without EDI binding
    frost.cells = {}
    local order = 0
    for gy = 1, frost.gh do
      for gx = 1, frost.gw do
        order = order + 1
        local c = Instance.new("Frame", layer)
        c.Name = "F" .. order
        c.BorderSizePixel = 0
        c.AnchorPoint = Vector2.new(0.5, 0.5)
        c.Position = UDim2.new((gx - 0.5) / frost.gw, 0, (gy - 0.5) / frost.gh, 0)
        c.Size = UDim2.new(1 / frost.gw + 0.02, 0, 1 / frost.gh + 0.02, 0)
        c.BackgroundColor3 = Color3.new(1, 1, 1)
        c.BackgroundTransparency = 0.5
        c.ZIndex = 0
        frost.cells[order] = c
      end
    end
    frost.ok = false -- EDI path off; fallback paints frames below
  end

  local grid = {}
  for i = 1, frost.gw * frost.gh do grid[i] = { 0.5, 0.5, 0.55 } end
  frost.grid = grid

  local rcParams = RaycastParams.new()
  rcParams.FilterType = Enum.RaycastFilterType.Exclude
  rcParams.IgnoreWater = true
  rcParams.RespectCanCollide = false

  local function sampleCell(cam, ap, as, vp, gx, gy)
    local u = (gx + 0.2 + 0.6 * (((gx * 7 + gy * 3) % 11) / 11)) / frost.gw
    local v = (gy + 0.2 + 0.6 * (((gy * 11 + gx * 5) % 13) / 13)) / frost.gh
    local px, py = ap.X + u * as.X, ap.Y + v * as.Y
    if px < 0 or py < 0 or px >= vp.X or py >= vp.Y then return end
    local ray = cam:ViewportPointToRay(math.clamp(px, 0, vp.X - 1), math.clamp(py, 0, vp.Y - 1))
    local hit = workspace:Raycast(ray.Origin, ray.Direction * 600, rcParams)
    local idx = (gy - 1) * frost.gw + gx
    if hit and hit.Instance and hit.Instance:IsA("BasePart") then
      local c = hit.Instance.Color
      grid[idx] = { c.R, c.G, c.B }
    else
      -- sky / void fallback: average ambient tones
      local a, o = Lighting.Ambient, Lighting.OutdoorAmbient
      grid[idx] = { (a.R + o.R) * 0.5 + 0.1, (a.G + o.G) * 0.5 + 0.1, (a.B + o.B) * 0.5 + 0.15 }
    end
  end

  frost.chunk = function(budgetMs)
    local cam = workspace.CurrentCamera
    if not cam then return end
    local as = win.AbsoluteSize
    if as.X < 60 or as.Y < 60 then return end
    local pg = lp:FindFirstChild("PlayerGui")
    local ch = lp.Character
    local fil = { pg }
    if ch then fil[#fil + 1] = ch end
    pcall(function() rcParams.FilterDescendantsInstances = fil end)
    local ap, vp = win.AbsolutePosition, cam.ViewportSize
    local t0 = os.clock()
    for _ = 1, 3 do -- 3 rows (36 rays) per frame, budget-checked
      local gy = (frost.rowNext % frost.gh) + 1
      frost.rowNext = frost.rowNext + 1
      for gx = 1, frost.gw do
        sampleCell(cam, ap, as, vp, gx, gy)
      end
if (os.clock() - t0) * 1000 > budgetMs then break end
    end
    end
  end

  local function frostApply()
  local gw, gh, grid = frost.gw, frost.gh, frost.grid
  if not grid then return end
  -- frost strength -> box-blur radius in cells; 100+ => heavy diffusion
  local R = math.clamp(math.floor((G.Frost or 100) * 0.055 + 0.5), 2, 6)
  local aR, aG, aB = {}, {}, {}
  for i = 1, gw * gh do
    aR[i], aG[i], aB[i] = grid[i][1], grid[i][2], grid[i][3]
  end
  for _ = 1, 3 do -- H / V / H passes ~ gaussian
    local t1R, t1G, t1B = {}, {}, {}
    for gy = 1, gh do
      local base = (gy - 1) * gw
      for gx = 1, gw do
        local sr, sg, sb, n = 0, 0, 0, 0
        for k = -R, R do
          local i = base + math.clamp(gx + k, 1, gw)
          sr = sr + aR[i]; sg = sg + aG[i]; sb = sb + aB[i]; n = n + 1
        end
        t1R[base + gx], t1G[base + gx], t1B[base + gx] = sr / n, sg / n, sb / n
      end
    end

    for gx = 1, gw do
      for gy = 1, gh do
        local sr, sg, sb, n = 0, 0, 0, 0
        for k = -R, R do
          local i = (math.clamp(gy + k, 1, gh) - 1) * gw + gx
          sr = sr + t1R[i]; sg = sg + t1G[i]; sb = sb + t1B[i]; n = n + 1
        end
        local i2 = (gy - 1) * gw + gx
        aR[i2], aG[i2], aB[i2] = sr / n, sg / n, sb / n
      end
    end
  end

  if frost.ok and frost.edi then
    -- bilinear upscale into the pane EDI (RGBA bytes) + soft lum lift
    local w, h = frost.res.X, frost.res.Y
    local buf = buffer.create(w * h * 4)
    local oGw, oGh = gw - 1, gh - 1
    for py = 0, h - 1 do
      local gyF = (py + 0.5) / h * oGh
      local gy0 = math.floor(gyF)
      local fy = gyF - gy0
      local gy1 = math.min(gy0 + 1, oGh)
      local rowBase = py * w * 4
      for px = 0, w - 1 do
        local gxF = (px + 0.5) / w * oGw
        local gx0 = math.floor(gxF)
        local fx = gxF - gx0
        local gx1 = math.min(gx0 + 1, oGw)
        local L, Rt = (1 - fx) * (1 - fy), fx * (1 - fy)
        local Dn, Rd = (1 - fx) * fy, fx * fy
        local i00, i10 = gy0 * gw + gx0 + 1, gy0 * gw + gx1 + 1
        local i01, i11 = gy1 * gw + gx0 + 1, gy1 * gw + gx1 + 1
        local r = aR[i00] * L + aR[i10] * Rt + aR[i01] * Dn + aR[i11] * Rd
        local g = aG[i00] * L + aG[i10] * Rt + aG[i01] * Dn + aG[i11] * Rd
        local b = aB[i00] * L + aB[i10] * Rt + aB[i01] * Dn + aB[i11] * Rd
        local lift = 0.16 * (r * 0.3 + g * 0.5 + b * 0.2)
        r = r + (1 - r) * lift
        g = g + (1 - g) * lift
        b = b + (1 - b) * lift
        local off = rowBase + px * 4
        buffer.writeu8(buf, off, math.clamp(math.floor(r * 255 + 0.5), 0, 255))
        buffer.writeu8(buf, off + 1, math.clamp(math.floor(g * 255 + 0.5), 0, 255))
        buffer.writeu8(buf, off + 2, math.clamp(math.floor(b * 255 + 0.5), 0, 255))
        buffer.writeu8(buf, off + 3, 255)
      end
    end
    pcall(function() frost.edi:WritePixelsBuffer(Vector2.zero, buf) end)
    frost.img.ImageTransparency = math.clamp(1 - (0.18 + 0.40 * math.min(1, (G.Frost or 100) / 100)), 0, 1)
  else
    -- fallback painting: cell frames get the blurred colors directly
    if frost.cells then
      for i = 1, gw * gh do
        local c = frost.cells[i]
        if c then c.BackgroundColor3 = Color3.new(math.clamp(aR[i], 0, 1), math.clamp(aG[i], 0, 1), math.clamp(aB[i], 0, 1)) end
      end
    end
  end
end

-- ============================================== full-window drag layer
-- Active frame under ALL content: dragging works from anywhere on the glass.
-- Interactive controls (TextButtons / resize grip) sit above it and opt out.
local rh -- resize grip handle, assigned in the RESIZE section (declared early for the hit test)
local dragL = Instance.new("Frame", win)
dragL.Name = "DragLayer"
dragL.BackgroundTransparency = 1
dragL.Size = UDim2.fromScale(1, 1)
dragL.Active = true
dragL.ZIndex = 0

dragL.InputBegan:Connect(function(io)
  if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
    if S.resizing then return end
    local x, y = io.Position.X, io.Position.Y
    local ap, as = win.AbsolutePosition, win.AbsoluteSize
    if x > ap.X + as.X - 34 and y > ap.Y + as.Y - 34 then return end -- bottom-right grip zone never drags
    for _, o in ipairs(gui:GetGuiObjectsAtPosition(x, y)) do
      if o == dragL then break end -- reached our layer: nothing interactive above
      if o:IsA("TextButton") or o == rh or rh:IsAncestorOf(o) then return end
    end
    S.dragging = { sx = x, sy = y, px = win.Position.X.Offset, py = win.Position.Y.Offset, moved = false }
    if S.pressOv then tw(S.pressOv, TI_PRT, { BackgroundTransparency = (G.PressOverlayOp or 0.94) }) end
  end
end)

-- ============================================== floating traffic lights (no bar)
local function dot(color, xoff)
  local b = Instance.new("Frame", win)
  b.Size = UDim2.fromOffset(14, 14)
b.Position = UDim2.new(0, 16 + xoff, 0, 14)
    b.BackgroundColor3 = color
    b.ZIndex = 3
  local hit = Instance.new("TextButton", b)
  hit.Text = ""
  hit.BackgroundTransparency = 1
  hit.Size = UDim2.fromScale(1.7, 1.7)
  hit.AnchorPoint = Vector2.new(0.5, 0.5)
  hit.Position = UDim2.fromScale(0.5, 0.5)
  hit.ZIndex = 4
  return b, hit
end

local closeDot, closeHit = dot(RED, 0)
local minDot,   minHit   = dot(YELLOW, 20)
local fullDot,  fullHit  = dot(GREEN, 40)
local dotTitle = Instance.new("Frame", win) -- hover proxy region for glyphs
dotTitle.Position = UDim2.new(0, 10, 0, 8)
dotTitle.Size = UDim2.fromOffset(74, 26)
dotTitle.BackgroundTransparency = 1

local gx = iconFx(closeDot, ICONS.x, 7, Color3.fromRGB(60, 30, 25), 0.1)
gx.AnchorPoint = Vector2.new(0.5, 0.5); gx.Position = UDim2.fromScale(0.5, 0.5); gx.ZIndex = 5; gx.Visible = false
local gm = iconFx(minDot, ICONS.minus, 7, Color3.fromRGB(60, 50, 10), 0.1)
gm.AnchorPoint = Vector2.new(0.5, 0.5); gm.Position = UDim2.fromScale(0.5, 0.5); gm.ZIndex = 5; gm.Visible = false
local ge = iconFx(fullDot, ICONS.maximize, 7, Color3.fromRGB(15, 60, 30), 0.1)
ge.AnchorPoint = Vector2.new(0.5, 0.5); ge.Position = UDim2.fromScale(0.5, 0.5); ge.ZIndex = 5; ge.Visible = false
dotTitle.MouseEnter:Connect(function() gx.Visible = true; gm.Visible = true; ge.Visible = true end)
dotTitle.MouseLeave:Connect(function() gx.Visible = false; gm.Visible = false; ge.Visible = false end)

-- ============================================== SIDEBAR
local sidebar = makeGlass(win, 16, { name = "Sidebar", tint = THEME.sideTint, baseT = THEME.sideT, innerRing = true, crisp = true })
sidebar.Position = UDim2.new(0, 34, 0, 34)
sidebar.Size = UDim2.new(0, 208, 1, -134)
S.sidebar = sidebar
sidebar.ZIndex = 3

local content = Instance.new("Frame", win)
content.Name = "Content"
content.Position = UDim2.new(0, 252, 0, 34)
content.Size = UDim2.new(1, -286, 1, -68)
content.BackgroundTransparency = 1

-- overview page
local ovPage = Instance.new("Frame", content)
ovPage.Name = "Overview"
ovPage.BackgroundTransparency = 1
ovPage.Size = UDim2.fromScale(1, 1)

local cntKind = txt(ovPage, "OVERVIEW", 10, Enum.Font.GothamBold, "dim", 0.25)
cntKind.Position = UDim2.new(0, 12, 0, 8)
cntKind.Size = UDim2.fromOffset(240, 12)
cntKind.TextXAlignment = Enum.TextXAlignment.Left

local cntTitle = txt(ovPage, "Coming Soon...", 24, Enum.Font.GothamBold, "hi")
cntTitle.Position = UDim2.new(0, 12, 0, 26)
cntTitle.Size = UDim2.new(1, -24, 0, 32)
cntTitle.TextXAlignment = Enum.TextXAlignment.Left

local cntBody = txt(ovPage, "This module is on the way.", 14, Enum.Font.Gotham, "dim", 0.2)
cntBody.Position = UDim2.new(0, 14, 0, 70)
cntBody.Size = UDim2.new(1, -28, 1, -90)
cntBody.TextXAlignment = Enum.TextXAlignment.Left
cntBody.TextYAlignment = Enum.TextYAlignment.Top
cntBody.TextWrapped = true

-- settings page (opens via profile card, behaves like a category)
local setPage = Instance.new("Frame", content)
setPage.Name = "Settings"
setPage.BackgroundTransparency = 1
setPage.Size = UDim2.fromScale(1, 1)
setPage.Visible = false

local setLbl = txt(setPage, "SETTINGS", 10, Enum.Font.GothamBold, "dim", 0.25)
setLbl.Position = UDim2.new(0, 12, 0, 8)
setLbl.Size = UDim2.fromOffset(240, 12)
setLbl.TextXAlignment = Enum.TextXAlignment.Left

local setTitle = txt(setPage, "Appearance", 24, Enum.Font.GothamBold, "hi")
setTitle.Position = UDim2.new(0, 12, 0, 26)
setTitle.Size = UDim2.new(1, -24, 0, 32)
setTitle.TextXAlignment = Enum.TextXAlignment.Left

local rows = {}
local function makeSwitchRow(y, iconId, label, sub, getOn)
  local rowIcon = icon(setPage, iconId, 16, "hi", 0.25)
  rowIcon.Position = UDim2.new(0, 14, 0, y + 4)
  rowIcon.ZIndex = 3

  local rowLabel = txt(setPage, label, 15, Enum.Font.GothamMedium, "hi", 0.1)
  rowLabel.Position = UDim2.new(0, 40, 0, y)
  rowLabel.Size = UDim2.new(1, -140, 0, 18)
  rowLabel.TextXAlignment = Enum.TextXAlignment.Left
  rowLabel.ZIndex = 3

  local rowSub = txt(setPage, sub, 11, Enum.Font.Gotham, "dim", 0.2)
  rowSub.Position = UDim2.new(0, 40, 0, y + 23)
  rowSub.Size = UDim2.new(1, -160, 0, 26)
  rowSub.TextWrapped = true
  rowSub.ZIndex = 3

  local pill = Instance.new("Frame", setPage)
  pill.Name = "Switch"
  pill.AnchorPoint = Vector2.new(1, 0)
  pill.Position = UDim2.new(1, -12, 0, y + 2)
  pill.Size = UDim2.fromOffset(48, 28)
  pill.BackgroundColor3 = GREEN
  pill.BorderSizePixel = 0
pill.ZIndex = 3
  corner(pill, 14)

  local knob = Instance.new("Frame", pill)
knob.Size = UDim2.fromOffset(24, 24)
  knob.BackgroundColor3 = Color3.new(1,1,1)
  knob.ZIndex = 4
  knob.Position = UDim2.new(0, 2, 0, 2)
  corner(knob, 12)

  local hit = Instance.new("TextButton", setPage)
  hit.Text = ""
  hit.BackgroundTransparency = 1
  hit.Position = UDim2.new(0, 0, 0, y - 8)
  hit.Size = UDim2.new(1, 0, 0, 56)
  hit.ZIndex = 2

  local row = {
    hit = hit,
    paint = function(instant)
      local on = getOn()
      local tPos = on and UDim2.new(1, -26, 0, 2) or UDim2.new(0, 2, 0, 2)
      local tBG  = on and GREEN or THEME.switchOff
      if instant then
        knob.Position = tPos
        pill.BackgroundColor3 = tBG
      else
        tw(knob, TI_POP, { Position = tPos })
        tw(pill, TI_UP,  { BackgroundColor3 = tBG })
      end
    end,
  }
  rows[#rows + 1] = row
  return row
end

local rowGlass = makeSwitchRow(70, ICONS.sliders, "Liquid Glass",
  "Frosted vibrancy over the world - or a flat opaque surface.",
  function() return S.mode == "glass" end)
local rowDark = makeSwitchRow(140, ICONS.moon, "Dark Mode",
  "Midnight surface - easier on the eyes.",
  function() return S.dark end)

-- ============================================== CATEGORIES (surface pills)
local cats = {}
local catPaint = {}

local function paintCat(b, hot, sel)
  tw(b, TI_HOT, { BackgroundTransparency = sel and THEME.pillSel or (hot and THEME.pillHot or THEME.pillT) })
end

local function catBtn(idx)
  local b = makeGlass(sidebar, 12, { name = "Cat" .. idx, tint = THEME.pillTint, baseT = THEME.pillT, interactive = true, elastic = true, glowMax = 0.14 })
  b.Size = UDim2.new(1, -14, 0, 46)
  b.Position = UDim2.new(0, 7, 0, 10 + (idx - 1) * 52)
  b.ZIndex = 5

  local mark = icon(b, ICONS.clock, 18, "hi", 0.1)
  mark.AnchorPoint = Vector2.new(0.5, 0.5)
  mark.Position = UDim2.new(0, 30, 0.5, 0)
  mark.ZIndex = 6

  local lb = txt(b, "Coming Soon...", 14, Enum.Font.GothamMedium, "hi", 0.08)
  lb.Position = UDim2.new(0, 52, 0.5, -8)
  lb.Size = UDim2.new(1, -60, 0, 16)
  lb.TextXAlignment = Enum.TextXAlignment.Left
  lb.ZIndex = 6

  local hit = Instance.new("TextButton", b)
  hit.Text = ""
  hit.BackgroundTransparency = 1
  hit.Size = UDim2.fromScale(1, 1)
  hit.ZIndex = 7

  local selected = (idx == S.sel)

  hit.MouseEnter:Connect(function() if not selected then paintCat(b, true, false) end end)
  hit.MouseLeave:Connect(function() paintCat(b, false, selected) end)
  hit.MouseButton1Click:Connect(function()
    S.sel = idx
    for i = 1, 2 do
      if i == idx then paintCat(cats[i], false, true) else paintCat(cats[i], false, false) end
    end
    S.showPage("overview")
  end)

  pressable(b, b.Size, hit)
  paintCat(b, false, selected)
  cats[idx] = b
  catPaint[idx] = function(hot, sel) paintCat(b, hot, sel) end
end

catBtn(1)
catBtn(2)

-- ============================================== PROFILE CARD (opens settings page)
local pc = makeGlass(sidebar, 12, { name = "Profile", tint = THEME.pillTint, baseT = THEME.profT, interactive = true, elastic = true, glowMax = 0.12 })
pc.Size = UDim2.new(1, -14, 0, 58)
pc.Position = UDim2.new(0, 7, 1, -66)
pc.ZIndex = 5

local pfp = Instance.new("ImageLabel", pc)
pfp.Size = UDim2.fromOffset(38, 38)
pfp.Position = UDim2.new(0, 10, 0.5, -19)
pfp.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
pfp.BorderSizePixel = 0
pfp.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(lp.UserId) .. "&w=150&h=150"
pfp.ZIndex = 6
  corner(pfp, 19)

local nameT = txt(pc, lp.DisplayName or lp.Name, 13, Enum.Font.GothamBold, "hi")
nameT.Position = UDim2.new(0, 58, 0, 13)
nameT.Size = UDim2.new(1, -80, 0, 15)
nameT.TextXAlignment = Enum.TextXAlignment.Left
nameT.ZIndex = 6

local gameT = txt(pc, "Now playing: " .. game.Name, 10, Enum.Font.Gotham, "dim", 0.15)
gameT.Position = UDim2.new(0, 58, 0, 31)
gameT.Size = UDim2.new(1, -80, 0, 14)
gameT.TextXAlignment = Enum.TextXAlignment.Left
gameT.TextTruncate = Enum.TextTruncate.AtEnd
gameT.ZIndex = 6

local gear = icon(pc, ICONS.settings, 14, "dim", 0.1)
gear.Position = UDim2.new(1, -28, 0.5, -7)
gear.ZIndex = 6

local pbtn = Instance.new("TextButton", pc)
pbtn.Text = ""
pbtn.BackgroundTransparency = 1
pbtn.Size = UDim2.fromScale(1, 1)
pbtn.ZIndex = 7
pressable(pc, pc.Size, pbtn)
pc.MouseEnter:Connect(function() tw(pc, TI_HOT, { BackgroundTransparency = THEME.profHot }) end)
pc.MouseLeave:Connect(function() tw(pc, TI_HOT, { BackgroundTransparency = THEME.profT }) end)

-- ============================================== page switching
local settingsOpen = false
function S.showPage(which)
  if which == "settings" then
    settingsOpen = true
    ovPage.Visible = false
    setPage.Visible = true
    for _, r in ipairs(rows) do r.paint(true) end
    for i = 1, 2 do paintCat(cats[i], false, false) end
  else
    settingsOpen = false
    ovPage.Visible = true
    setPage.Visible = false
  end

end

pbtn.MouseButton1Click:Connect(function()
  if settingsOpen then
    S.showPage("overview")
    S.sel = 0
  else
    S.showPage("settings")
  end
end)

rowGlass.hit.MouseButton1Click:Connect(function()
  S.mode = (S.mode == "glass") and "opaque" or "glass"
  rowGlass.paint(false)
  S.applyMode()
end)

rowDark.hit.MouseButton1Click:Connect(function()
  S.dark = not S.dark
  rowDark.paint(false)
  THEME = THEMES[S.dark and "dark" or "light"]
  S.applyTheme()
end)

-- ============================================== MATERIAL MODE
function S.applyMode()
  local glass = (S.mode == "glass")
  tw(S.win, TI_SM, {
    BackgroundColor3 = glass and THEME.winTint or THEME.opqWin,
    BackgroundTransparency = glass and THEME.winT or 0,
  })
  tw(S.sidebar, TI_SM, {
    BackgroundColor3 = glass and THEME.sideTint or THEME.opqSide,
    BackgroundTransparency = glass and THEME.sideT or THEME.opqSideT,
  })
  for i = 1, 2 do
    tw(cats[i], TI_SM, { BackgroundColor3 = glass and THEME.pillTint or THEME.opqPill })
  end
  tw(pc, TI_SM, { BackgroundColor3 = glass and THEME.pillTint or THEME.opqPill })
  for _, e in ipairs(rimSet) do
    local t = glass and (1 - 0.35 * (G.Aberration or 1)) or 1
    if not (G.LineFx ~= false) then t = 1 end -- borderless glass: no chromatic outlines
    tw(e.s1, TI_SM, { Transparency = t })
    tw(e.s2, TI_SM, { Transparency = t })
    if e.s3 then tw(e.s3, TI_SM, { Transparency = math.min(0.985, t + 0.08) }) end
  end
  -- glass-only material effects (refraction band, fresnel ring, rim light) vanish in opaque
  local showLines = glass and (G.LineFx ~= false)
  for _, e in ipairs(glassFx) do
    tw(e.o, TI_SM, { Transparency = showLines and e.base or 1 })
  end
  -- depth pass frames (top glow / bottom shade) are material too - fade in glass
  local depthVisible = glass
  for _, e in ipairs(glassFrames) do
    tw(e.o, TI_SM, { BackgroundTransparency = depthVisible and e.base or 1 })
  end
  -- backdrop frost layers belong to the glass material only
  for _, f in ipairs(frost.vis) do
    f.Visible = glass and not S.minimized
  end
  -- frost noise layers also belong to the glass material only
  if frost.noiseLayers then
    for _, nl in ipairs(frost.noiseLayers) do
      nl.Visible = glass and not S.minimized
    end
  end

end

-- ============================================== THEME
function S.applyTheme()
  for _, e in ipairs(textRefs) do
    tw(e.o, TI_SM, { TextColor3 = (e.r == "dim") and THEME.textDim or THEME.textHi })
  end
  for _, e in ipairs(iconRefs) do
    tw(e.o, TI_SM, { ImageColor3 = (e.r == "dim") and THEME.textDim or THEME.textHi })
  end
  for _, d in ipairs(gripDots) do
    tw(d, TI_SM, { BackgroundColor3 = THEME.grip })
  end
  for i, l in ipairs(shadowLayers) do
    tw(l, TI_SM, { BackgroundTransparency = THEME.shadowT })
  end
  for _, r in ipairs(rows) do r.paint(false) end
  -- retint the interaction layers from the theme matrix
  for _, e in ipairs(fxSet) do
    if e.ggrad then e.ggrad.Color = ColorSequence.new(THEME.glow) end
  end
  for _, e in ipairs(glassFrames) do
    local colr = (e.o.Name == "DepthTop") and THEME.depthTop or THEME.depthBottom
    e.o.BackgroundColor3 = colr
    if e.o:FindFirstChildOfClass("UIGradient") then
      e.o:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(colr, colr)
    end
  end
  S.applyMode()
end

-- ============================================== DRAG (whole window, from drag layer)
bind(UIS.InputChanged:Connect(function(io)
  if not S.dragging then return end
  if io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch then
    local dx = io.Position.X - S.dragging.sx
    local dy = io.Position.Y - S.dragging.sy
    if not S.dragging.moved and (math.abs(dx) + math.abs(dy)) < 4 then return end
    S.dragging.moved = true
    local vp = gui.AbsoluteSize
    local w = S.minimized and 150 or win.Size.X.Offset
    local nx = math.clamp(S.dragging.px + dx, -(w - 150), vp.X - 150)
    local ny = math.clamp(S.dragging.py + dy, 8, vp.Y - 60)
    win.Position = UDim2.fromOffset(nx, ny)
    syncShadow()
  end
end))
bind(UIS.InputEnded:Connect(function(io)
  if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
    if S.pressOv then tw(S.pressOv, TI_UP, { BackgroundTransparency = 1 }) end
    if S.dragging then
      S.winPos = Vector2.new(win.Position.X.Offset, win.Position.Y.Offset)
      S.dragging = nil
    end
  end
end))

-- ============================================== RESIZE
rh = Instance.new("Frame", win)
rh.Name = "Resize"
rh.AnchorPoint = Vector2.new(1, 1)
rh.Position = UDim2.new(1, -2, 1, -2)
rh.Size = UDim2.fromOffset(22, 22)
rh.BackgroundTransparency = 1
rh.ZIndex = 15
shapeGrip(rh).Position = UDim2.new(1, -16, 1, -16)

rh.InputBegan:Connect(function(io)
  if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
    S.dragging = nil -- resize locks the window in position - no drag while resizing
    S.resizing = { mx = io.Position.X, my = io.Position.Y, w = win.Size.X.Offset, h = win.Size.Y.Offset }
  end
end)
bind(UIS.InputChanged:Connect(function(io)
  if not S.resizing then return end
  if io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch then
    local dx = io.Position.X - S.resizing.mx
    local dy = io.Position.Y - S.resizing.my
    local vp = gui.AbsoluteSize
    local w = math.clamp(S.resizing.w + dx, S.minSize.X, vp.X - 24)
    local h = math.clamp(S.resizing.h + dy, S.minSize.Y, vp.Y - 24)
    win.Size = UDim2.fromOffset(w, h)
    S.winSize = Vector2.new(w, h)
    syncShadow()
  end
end))
bind(UIS.InputEnded:Connect(function(io)
  if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
    if S.resizing then S.resizing = nil end
  end
end))

-- ============================================== RED - KILL TOTALLY
closeHit.MouseButton1Click:Connect(function()
  UI.kill()
end)

-- ============================================== YELLOW - MINIMIZE
minHit.MouseButton1Click:Connect(function()
  S.minimized = not S.minimized
  if S.minimized then
    S.saved = { w = win.Size.X.Offset, h = win.Size.Y.Offset, x = win.Position.X.Offset, y = win.Position.Y.Offset }
    sidebar.Visible = false
    content.Visible = false
    for _, f in ipairs(frost.vis) do f.Visible = false end
    if frost.noiseLayers then for _, nl in ipairs(frost.noiseLayers) do nl.Visible = false end end
    for _, sw in ipairs(sweepList) do sw.f.Visible = false end
    twWin(TI_POP, { Size = UDim2.fromOffset(96, 38), Position = UDim2.new(1, -114, 1, -62) })
  else
    sidebar.Visible = true
    content.Visible = true
    for _, f in ipairs(frost.vis) do f.Visible = (S.mode == "glass") end
    if frost.noiseLayers then for _, nl in ipairs(frost.noiseLayers) do nl.Visible = (S.mode == "glass") end end
    local gv = S.saved or { w = UI.Config.StartSize.X, h = UI.Config.StartSize.Y, x = UI.Config.StartPos.X, y = UI.Config.StartPos.Y }
    S.winSize = Vector2.new(gv.w, gv.h)
    twWin(TI_POP, { Size = UDim2.fromOffset(gv.w, gv.h), Position = UDim2.fromOffset(gv.x, gv.y) })
  end
end)

-- ============================================== GREEN - FULLSCREEN
fullHit.MouseButton1Click:Connect(function()
  S.full = not S.full
  if S.full then
    S.savedFull = { w = win.Size.X.Offset, h = win.Size.Y.Offset, x = win.Position.X.Offset, y = win.Position.Y.Offset }
    twWin(TI_Q, { Size = UDim2.new(1, -24, 1, -24), Position = UDim2.fromOffset(12, 12) })
  else
    local gv = S.savedFull or { w = UI.Config.StartSize.X, h = UI.Config.StartSize.Y, x = UI.Config.StartPos.X, y = UI.Config.StartPos.Y }
    S.winSize = Vector2.new(gv.w, gv.h)
    twWin(TI_Q, { Size = UDim2.fromOffset(gv.w, gv.h), Position = UDim2.fromOffset(gv.x, gv.y) })
  end
end)

-- ============================================== LIQUID MOTION LOOP
local mouseTarget = Vector2.zero
bind(UIS.InputChanged:Connect(function(io)
  if io.UserInputType == Enum.UserInputType.MouseMovement then
    mouseTarget = Vector2.new(io.Position.X, io.Position.Y)
  end
end))

local t0 = os.clock()
local tickCount = 0
bind(RunSvc.RenderStepped:Connect(function(dt)
  if S.minimized then return end
  local t = os.clock() - t0
  local dtc = (type(dt) == "number" and dt > 0) and dt or (1 / 60)

  tickCount = tickCount + 1
  local slow = (tickCount % 2 == 0) -- 30Hz visual layers

  if slow then
    for i, e in ipairs(rimSet) do
      e.g1.Rotation = 225 + math.sin(t * 0.5 + i) * 10
      e.g2.Rotation = 45 - math.cos(t * 0.45 + i) * 10
    end
  end

  -- cursor-reactive pass (Pro ports): sheen follows cursor, rim chases it,
  -- springs pull interactive panes and drive hover scale
  if slow then
    for _, e in ipairs(fxSet) do
      local ap, as = e.pane.AbsolutePosition, e.pane.AbsoluteSize
      local nx, ny, inside = 0, 0, false
      if as.X > 0 and as.Y > 0 then
        local mx = mouseTarget.X - ap.X
        local my = mouseTarget.Y - ap.Y
        if mx >= 0 and my >= 0 and mx <= as.X and my <= as.Y then
          nx = math.clamp(mx / (as.X * 0.5), -1, 1)
          ny = math.clamp(my / (as.Y * 0.5), -1, 1)
          inside = true
        end
      if inside ~= e.hover then
        e.hover = inside
        if e.glow then tw(e.glow, TI_UP, { BackgroundTransparency = inside and 0 or 1 }) end
        if e.scaleSpr then
          springTarget(e.scaleSpr, (inside and not e.noScale) and (G.HoverScale or 1.02) or 1, 1)
        end
        if e.spring then springTarget(e.spring, 0, 0) end
      end
      if e.pane == win then
        if inside and S.winHover ~= true then S.hoverT0 = t end -- sweep cycle anchor
        S.winHover = inside
      end
      if e.ggrad then
        e.ggrad.Offset = Vector2.new(nx * 0.3, ny * 0.3)
      end
if e.spring and e.elastic then
        if not e.base then e.base = e.pane.Position end
        springTarget(e.spring, nx * (e.elastic or 6), ny * (e.elastic or 6))
      end
    end

  end
  end

  -- spring physics every frame (fixed-substep semi-implicit Euler)
  for _, e in ipairs(fxSet) do
    springStep(e.spring, dtc)
    springStep(e.scaleSpr, dtc)
    if e.elastic and e.base then
      local px = e.pane.Position
      if e.spring.x ~= px.X.Offset - e.base.X.Offset or e.spring.y ~= px.Y.Offset - e.base.Y.Offset then
        e.pane.Position = UDim2.new(
          e.base.X.Scale, e.base.X.Offset + e.spring.x,
          e.base.Y.Scale, e.base.Y.Offset + e.spring.y)
      end
      if e.scale and not e.noScale then e.scale.Scale = e.scaleSpr.x end
    end
  end

  -- shine sweeps: on hover, streaks slide in from the left and exit right,
  -- repeating with a gap; hidden the moment hover/opaque/minimized ends
  if sweepList[1] then
    local active = S.winHover and S.mode == "glass" and not S.minimized
    for _, sw in ipairs(sweepList) do
      local sp = sw.def
      if active then
        local phase = (t - (S.hoverT0 or t) - sp.delay) % (sp.dur + (G.SweepGap or 1.7))
        if phase < sp.dur then
          local p = phase / sp.dur
          sw.f.Position = UDim2.new(-0.55 + p * 2.1, 0, 0.5, 0)
          sw.f.BackgroundTransparency = math.clamp(1 - math.sin(p * math.pi) * sp.peak * (THEME.glareMul or 1), 0, 1)
          sw.f.Visible = true
        else
          sw.f.Visible = false
        end
      elseif sw.f.Visible then
        sw.f.Visible = false
      end
    end
  end

  -- localized backdrop frost: sample a grid chunk each frame + periodic write
  if S.mode == "glass" and not S.minimized then
    frost.chunk(2.5) -- ms budget per frame
    if t - frost.tLast >= frost.refresh then
      frost.tLast = t
      frostApply()
    end
  end
end))

-- ============================================== ALWAYS-ON-TOP WATCHDOG
bind(task.spawn(function()
  while UI._gui do
    task.wait(2)
    pcall(function()
      local top = -1
      for _, g in ipairs(lp.PlayerGui:GetChildren()) do
        if g ~= UI._gui and g:IsA("ScreenGui") and g.DisplayOrder > top then top = g.DisplayOrder end
      end
      if top >= UI._gui.DisplayOrder then UI._gui.DisplayOrder = math.min(2147483647, top + 1) end
    end)
  end
end))

-- ============================================== FIRST PAINT
for _, r in ipairs(rows) do r.paint(true) end
S.applyTheme()

local refW = win.Size
local popW = UDim2.new(refW.X.Scale, refW.X.Offset * 0.94, refW.Y.Scale, refW.Y.Offset * 0.94)
win.Size = popW
syncShadow()
twWin(TI_POP, { Size = refW })

end -- UI.init

function UI.kill()
  for _, c in ipairs(UI._cons or {}) do
    pcall(function()
      if typeof(c) == "RBXScriptConnection" then c:Disconnect() end
    end)
  end
  UI._cons = nil
  pcall(function() if UI._frostEdi then UI._frostEdi:Destroy() end end)
  pcall(function() if UI._shadowRoot then UI._shadowRoot:Destroy() end end)
  pcall(function() if UI._gui then UI._gui:Destroy() end end)
  UI._shadowRoot, UI._gui = nil, nil
end

-- auto-boot when the chunk itself is executed directly (plain paste).
-- If the loader drove init() already, the idempotent guard makes this a no-op.
task.spawn(function()
  if not UI._gui then
    local ok, err = pcall(function() UI.init() end)
    if not ok then
      warn("[N's 'tion] auto-boot ERROR: " .. tostring(err))
    elseif not UI._gui then
      warn("[N's 'tion] auto-boot failed - call UI.init() manually")
    end
  end
end)

return UI