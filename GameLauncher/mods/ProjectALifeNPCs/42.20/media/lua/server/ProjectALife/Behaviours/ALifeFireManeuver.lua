require "ProjectALife/Compat/ALifeFeatureGate"
require "ProjectALife/Senses/ALifeSight"

ProjectALife = ProjectALife or {}
ProjectALife.FireManeuver = { nextAt = {}, states = {}, metrics = { searches=0, rays=0, refused=0,
    advanced=0, peeks=0, returned=0, aborted=0 }, bearings = { 0, 0.5, -0.5, 1, -1, 1.5, -1.5, 3.14 } }

function ProjectALife.FireManeuver.enabled()
    return ProjectALife.FeatureGate.flag("Combat_FireManeuver", true)
end

function ProjectALife.FireManeuver.number(key, fallback, low, high)
    return ProjectALife.FeatureGate.number(key, fallback, low, high)
end

function ProjectALife.FireManeuver.ray(budget, x,y,z, tx,ty,tz)
    local self = ProjectALife.FireManeuver
    local tick = math.floor(ProjectALife.Combat.nowMs() / 100)
    if self.tick ~= tick then self.tick, self.rays = tick, 0 end
    if budget.left <= 0 or (self.rays or 0) >= 64 then return nil end
    budget.left, self.rays = budget.left - 1, (self.rays or 0) + 1
    self.metrics.rays = self.metrics.rays + 1
    return ProjectALife.Sight.between(x,y,z,tx,ty,tz)
end

function ProjectALife.FireManeuver.route(shell, from, point)
    local cell = type(getCell) == "function" and getCell() or nil
    local guard = ProjectALife.AIFence
    if cell == nil or guard == nil or type(guard.stepClear) ~= "function" then return false end
    if math.abs(shell:getZ()-point.z)>=0.4 then return false end
    local dx,dy = point.x-from.x,point.y-from.y
    local steps = math.ceil(math.sqrt(dx*dx+dy*dy)*4)
    if steps > 96 then return false end
    local x,y = from.x,from.y
    local count,level = math.max(1,steps),math.floor(point.z)
    local doneX,doneY
    for index=1,count do
        local nx,ny = from.x+dx*index/count,from.y+dy*index/count
        local tileX,tileY = math.floor(nx),math.floor(ny)
        if tileX ~= doneX or tileY ~= doneY then
            local square = cell:getGridSquare(math.floor(x),math.floor(y),level)
            local landing = cell:getGridSquare(tileX,tileY,level)
            if square == nil or landing == nil then return false end
            if (tileX~=math.floor(shell:getX()) or tileY~=math.floor(shell:getY()))
                    and landing:isFree(false) ~= true then return false end
            if not guard.stepClear(shell,square,x,y,nx,ny) then return false end
            if type(landing.haveFire) == "function" and landing:haveFire() then return false end
            doneX,doneY = tileX,tileY
        end
        x,y = nx,ny
    end
    return true
end

function ProjectALife.FireManeuver.peek(shell,target,point,budget)
    local self = ProjectALife.FireManeuver
    for _,offset in ipairs({{0,1},{0,-1},{1,0},{-1,0}}) do
        local nextPoint={x=point.x+offset[1],y=point.y+offset[2],z=point.z}
        if self.route(shell,point,nextPoint) and self.ray(budget,target:getX(),target:getY(),target:getZ(),
                nextPoint.x,nextPoint.y,nextPoint.z)=="clear" then return nextPoint end
    end
    return nil
end

function ProjectALife.FireManeuver.find(shell,target,options)
    local self = ProjectALife.FireManeuver
    local retreat = options.mode == "retreat"
    if retreat then
        if not ProjectALife.FeatureGate.flag("Combat_RetreatLOS",true) then return nil end
    elseif not self.enabled() then return nil end
    if shell == nil or target == nil or math.abs(shell:getZ()-target:getZ())>=0.4 then return nil end
    local origin={x=shell:getX(),y=shell:getY(),z=shell:getZ()}
    local dx,dy=target:getX()-origin.x,target:getY()-origin.y
    local distance=math.sqrt(dx*dx+dy*dy)
    if distance<4 then return nil end
    dx,dy=dx/distance,dy/distance
    if retreat then dx,dy=-dx,-dy end
    local radius=retreat and math.min(18,tonumber(options.distance) or 12)
        or self.number("Combat_ForwardCoverTiles",4,2,6)
    local budget,best,score={left=16},nil,nil
    self.metrics.searches=self.metrics.searches+1
    for _,scale in ipairs({0.5,1}) do
        for _,angle in ipairs(self.bearings) do
            local cs,sn=math.cos(angle),math.sin(angle)
            local point={x=math.floor(origin.x+(dx*cs-dy*sn)*radius*scale)+0.5,
                y=math.floor(origin.y+(dy*cs+dx*sn)*radius*scale)+0.5,z=origin.z}
            local px,py=point.x-origin.x,point.y-origin.y
            point.toSelf=math.sqrt(px*px+py*py)
            point.toThreat=math.sqrt((point.x-target:getX())^2+(point.y-target:getY())^2)
            local progress=distance-point.toThreat
            if point.toSelf<=radius+0.01 and point.toSelf>=1 and ((retreat and progress<=0)
                    or (not retreat and progress>=1)) and self.route(shell,origin,point)
                    and (retreat or options.actor==nil or ProjectALife.Combat.positionOfferAllowed(options.actor,shell,point,
                        {ranged=true,weapon=options.weapon,target=target})) then
                local sight=self.ray(budget,target:getX(),target:getY(),target:getZ(),point.x,point.y,point.z)
                if ProjectALife.Sight.hides(sight) then
                    point.peek=not retreat and self.peek(shell,target,point,budget) or nil
                    if retreat or (point.peek~=nil and (options.actor==nil or ProjectALife.Combat.positionOfferAllowed(options.actor,shell,point.peek,
                            {ranged=true,weapon=options.weapon,target=target}))) then
                        local rank=point.toSelf-progress*0.5
                        if score==nil or rank<score then best,score=point,rank end
                    end
                end
            end
            if budget.left<=0 then break end
        end
        if budget.left<=0 then break end
    end
    return best
end

function ProjectALife.FireManeuver.clear(shell, reason)
    local self=ProjectALife.FireManeuver
    local state=self.states[shell]
    self.states[shell]=nil
    if state~=nil then
        if reason~="returned" then self.metrics.aborted=self.metrics.aborted+1 end
        if ProjectALife.AIFence.drivesBody(shell)==true then ProjectALife.Combat.cancelPath(shell) end
        local aim=ProjectALife.Combat.aimState[shell]
        if aim then aim.maneuver=nil; aim.maneuverCancelled=true end
    end
    if ProjectALife.SquadTactics and ProjectALife.SquadTactics.clearManeuver then
        ProjectALife.SquadTactics.clearManeuver(shell,reason)
    end
end

function ProjectALife.FireManeuver.start(actor,shell,target,point,now)
    local self=ProjectALife.FireManeuver
    self.nextAt[actor.uid]=now+8000
    local state={actor=actor, generation=actor.generation,target=target,identity=ProjectALife.TargetPolicy.identity(target),
        cover=point,peek=point.peek,stage="cover",untilMs=now+5000,totalUntilMs=now+13000}
    self.states[shell]=state
    ProjectALife.Combat.aimStateFor(shell).maneuverCancelled=nil
    self.metrics.advanced=self.metrics.advanced+1
    return state
end

function ProjectALife.FireManeuver.valid(actor,shell,target,weapon,now,state)
    local self=ProjectALife.FireManeuver
    local live=ProjectALife.ActorRegistry.read(actor.uid)
    local binding=ProjectALife.Watchdog.bindings[actor.uid]
    local activity=ProjectALife.DecisionLoop and ProjectALife.DecisionLoop.states[actor.uid]
    return self.enabled() and now<state.totalUntilMs and shell:isDead()~=true
        and binding~=nil and binding.shell==shell
        and activity~=nil and activity.kind=="combat"
        and live~=nil and live.generation==state.generation
        and target==state.target and ProjectALife.TargetPolicy.canAttack(target,state.identity,actor)
        and ProjectALife.Combat.hostileToActor(actor,target,shell)
        and ProjectALife.AIFence.drivesBody(shell)==true
        and ProjectALife.Combat.isRanged(weapon) and ProjectALife.Combat.currentAmmo(weapon)>0
        and ProjectALife.ModuleRegistry.allows(actor,"cover")
        and ProjectALife.Survival.evaluate(actor,shell,target,now)=="fight"
        and ProjectALife.Combat.positionOfferAllowed(actor,shell,state.cover,{ranged=true,weapon=weapon,target=target})
end

function ProjectALife.FireManeuver.holdPending(shell)
    if ProjectALife.AIFence.drivesBody(shell)~=true then return end
    ProjectALife.Combat.cancelPath(shell)
    ProjectALife.Combat.pathRequests[shell]=nil
end

function ProjectALife.FireManeuver.step(actor,shell,target,weapon,now,aim,phase)
    local self=ProjectALife.FireManeuver
    local state=self.states[shell]
    if state==nil then
        for _,pair in pairs(ProjectALife.SquadTactics.maneuvers) do
            if pair.uid==actor.uid then
                if target~=pair.target or ProjectALife.Combat.currentAmmo(weapon)<=0
                        or not ProjectALife.SquadTactics.maneuverValid(pair,now) then
                    ProjectALife.SquadTactics.clearManeuver(pair.pin,"wait_invalid")
                    return "resume"
                end
                if not pair.fired then
                    self.holdPending(shell)
                    return "hold"
                end
                aim.nextPositionAskMs=now
                return "resume"
            end
        end
        if aim.maneuverCancelled then aim.maneuverCancelled=nil; return "resume" end
        return nil
    end
    if not self.valid(actor,shell,target,weapon,now,state) then self.clear(shell,"invalid"); return "resume" end
    local point=state.stage=="peek" and state.peek or state.cover
    if state.stage=="fire" then
        if now<state.untilMs and state.ammo-ProjectALife.Combat.currentAmmo(weapon)<2 then return nil end
        if phase=="windup" or phase=="cycle_action" or phase=="recovery" then return nil end
        state.stage,state.untilMs="return",now+2500
        point=state.cover
    end
    if state.stage=="wait" then
        if now<state.untilMs then return "hold" end
        if not self.route(shell,state.cover,state.peek) then self.clear(shell,"peek_blocked"); return "resume" end
        state.stage,state.untilMs="peek",now+2500
        point=state.peek
    end
    if (shell:getX()-point.x)^2+(shell:getY()-point.y)^2<=0.16
            and math.abs(shell:getZ()-point.z)<0.4 then
        ProjectALife.Combat.cancelPath(shell)
        if state.stage=="cover" then state.stage,state.untilMs="wait",now+350; return "hold" end
        if state.stage=="peek" then
            state.stage,state.untilMs="fire",now+self.number("Combat_PeekWindowMs",1200,600,2000)
            state.ammo=ProjectALife.Combat.currentAmmo(weapon)
            self.metrics.peeks=self.metrics.peeks+1
            aim.readyAtMs=nil
            ProjectALife.Combat.setAimWalk(shell,true,"maneuver_peek")
            ProjectALife.Combat.faceTarget(shell,target)
            return "aim"
        end
        if state.stage=="return" then
            self.metrics.returned=self.metrics.returned+1
            self.clear(shell,"returned")
            return "resume"
        end
    end
    if now>=state.untilMs or not self.route(shell,{x=shell:getX(),y=shell:getY(),z=shell:getZ()},point) then
        self.clear(shell,"leg_failed"); return "resume"
    end
    ProjectALife.Combat.setAimWalk(shell,false,"maneuver_leg")
    ProjectALife.Combat.pathToward(shell,point,"walk",false)
    return "hold"
end

function ProjectALife.FireManeuver.offer(actor,shell,context)
    local self=ProjectALife.FireManeuver
    if not self.enabled() or context.hurt or context.reloading or not context.ranged
            or context.target==nil or context.threatIsGunman~=true then return nil end
    if (tonumber(self.nextAt[actor.uid]) or 0)>context.now or context.now<(tonumber(context.coverUntilMs) or 0) then return nil end
    if ProjectALife.Combat.peekKind(context.target)=="zombie"
            or ProjectALife.AIFence.drivesBody(shell)~=true
            or ProjectALife.Perception.visible(shell,context.target)~=true
            or ProjectALife.Survival.evaluate(actor,shell,context.target,context.now)~="fight" then return nil end
    local point=ProjectALife.ModuleCover.find(shell,context.target,{mode="forward",actor=actor,weapon=context.weapon,range=context.range})
    if point==nil then self.nextAt[actor.uid]=context.now+8000; return nil end
    if not ProjectALife.Combat.positionOfferAllowed(actor,shell,point,context) then return nil end
    local ready,waiting=ProjectALife.SquadTactics.maneuverReady(actor,shell,context.target,point,context.now)
    if not ready then
        if waiting=="pending" then self.holdPending(shell) end
        return nil,waiting
    end
    point.reason,point.pace,point.holdMs,point.legMs="cover_forward","walk",8000,5000
    point.maneuver=true
    return point
end

function ProjectALife.FireManeuver.sweep()
    local self=ProjectALife.FireManeuver
    local combat=ProjectALife.Combat
    if combat==nil or type(combat.nowMs)~="function" then return end
    local now=combat.nowMs()
    if now<(self.sweepAt or 0) then return end
    self.sweepAt=now+100
    for shell,state in pairs(self.states) do
        if not self.valid(state.actor,shell,state.target,combat.weaponFor(shell),now,state) then self.clear(shell,"sweep") end
    end
    local tactics=ProjectALife.SquadTactics
    if tactics and tactics.maneuvers then
        for _,pair in pairs(tactics.maneuvers) do
            if not tactics.maneuverValid(pair,now) then tactics.clearManeuver(pair.pin,"sweep") end
        end
    end
end

if type(Events)=="table" and Events.OnTick and type(Events.OnTick.Add)=="function" then
    Events.OnTick.Add(ProjectALife.FireManeuver.sweep)
end

return ProjectALife.FireManeuver
