require "WaterRestoration/WR_Power"
function WR.drawPowerDisplay(panel,state,x,y,w,dark)
 local g=state.generator or {};local fuel=g.fuel or 0
 local function label(key,value,dy)
  local t=getText((dark and "IGUI_WR_Gen_" or "IGUI_WR_LaptopPower_")..key)..(value and (": "..value) or "")
  if dark then panel:ink(t,x+20,y+dy) else panel:label(t,x+20,y+dy) end
 end
 panel:drawRect(x,y,w,298,1,dark and .07 or .80,dark and .13 or .83,dark and .10 or .78)
 label("Energy",WR.Power.gridAvailable(state) and getText("IGUI_WR_Power_Grid") or getText((dark and "IGUI_WR_Gen_" or "IGUI_WR_LaptopPower_")..(WR.Power.generatorAvailable(state) and "Running" or "NoPower")),18)
 label("FuelAmount",string.format("%.1f / 80 L",fuel),60)
 panel:drawRect(x+20,y+91,w-40,16,1,.14,.18,.14)
 panel:drawRect(x+22,y+93,(w-44)*math.min(1,fuel/80),12,1,.58,.72,.42)
 label("Remaining",string.format("%.1f d",WR.Power.hours({fuel=fuel})/24),128)
 label("Consumption",nil,170)
 label("Condition",string.format("%.0f%%",g.condition or 0),212)
 label("Minimum",nil,254)
end
