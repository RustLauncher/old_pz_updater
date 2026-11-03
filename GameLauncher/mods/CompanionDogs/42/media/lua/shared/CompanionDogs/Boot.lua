CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

-- Carrega antes do Perf.lua (LoadDirBase ordena por caminho em minusculas, 'boot' < 'perf').
-- Invertido, o stub no-op daqui apaga a instrumentacao inteira em silencio.

CD.MODULE = "CompanionDogs"

CD.BUILD = "0.7.4 (2026-09-04)"

CD.VERSION = string.match(CD.BUILD, "^[%d%.]+") or "?"
CD.LOGTAG = "[CompanionDogs " .. CD.VERSION .. "] "

---Prints msg with the mod tag and version in front.
---@param msg any
function CD.log(msg)
    print(CD.LOGTAG .. tostring(msg))
end

CD.log("starting Companion Dogs " .. CD.BUILD)

---@param ev table engine event, such as Events.OnTick
---@param fn function
---@param _key string zone the handler is credited to
CD.evAdd = function(ev, fn, _key) ev.Add(fn) end
---@param _k string zone the call is credited to
---@param fn function
---@param a any
---@param b any
---@param c any
---@return any r1 first result of fn
---@return any r2 second result of fn
CD.pz = function(_k, fn, a, b, c) return fn(a, b, c) end
CD.pzd = CD.pz
---@param _k string zone key
---@param fn function
---@return function
---@nodiscard
CD.pzWrap = function(_k, fn) return fn end
---@type fun(key: string)
CD.perfEnter = function() end
---@type fun()
CD.perfExit = function() end
---@type fun(key: string, n: number|nil)
CD.perfCount = function() end
---@type fun(key: string, v: number)
CD.perfGauge = function() end
---@type fun(): boolean|nil
CD.perfIn = function() return nil end
---@type fun(): boolean|nil
CD.perfIn2 = function() return nil end
---@type fun(key: string, t0: boolean|nil)
CD.perfOut = function() end
---@type fun(key: string, t0: boolean|nil)
CD.perfOut2 = function() end
---@type fun(t0: number|nil)
CD.perfSample = function() end
---@type fun()
CD.perfTickEnd = function() end
---@type fun(): integer
CD.perfApplyLevel = function() return 0 end
CD._perfLv = 0
CD._perfCnt = {}
CD._perfWinGauge = {}

CD.DEBUG_ALL = false
CD.PERF_DEBUG = false

CD.DOG_REG = true
