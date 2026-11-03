ProjectALife = ProjectALife or {}

local BehaviorSettings = {
    endurance = {

        maximum = 140,
        initial = 130,
        walkDrainPerSecond = 0.25,

        runDrainPerSecond = 0.4,

        sprintDrainPerSecond = 1.0,
        combatDrainPerSecond = 1.0,

        pursuitRecoveryPerSecond = 5.0,

        sprintResume = 55,
        retreatDrainPerSecond = 1.2,
        fearDrainScale = 1.8,
        idleRecoveryPerSecond = 9.0,
        cautiousRecoveryPerSecond = 4.0,
        attackCost = 3.0,
        damageCost = 10.0,
        sprintMinimum = 34,

        jogMinimum = 18,

        sprintProximityFloor = 4.5,
        retreatThreshold = 24,
        reengageThreshold = 72,
        damageRetreatMs = 2600,
        minimumRetreatMs = 2200,
        persistenceIntervalMs = 1000,

        tiredTempoMax = 1.35,
        tiredTempoBelow = 0.5,
    },

    gait = {

        sprinterPercent = 50,

        thicketSpeed = 0.75,

        limpTempo = 0.66,

        leaseMs = 1200,

        sprinter = {
            pace = "sprint",
            drainScale = 1.15,
            recoveryScale = 0.85,
        },

        jogger = {
            pace = "run",
            drainScale = 0.7,
            recoveryScale = 1.3,
        },
    },
    movement = {

        sprintEnabled = true,

        runActiveMs = 850,
        runCycleMs = 14000,
        patrolTimeoutMs = 18000,

        patrolPauseMinimumMs = 250,
        patrolPauseMaximumMs = 700,
        pursuitRepathMs = 700,
        combatRepathDistance = 1.5,

        stallMs = 800,
        pathStartupGraceMs = 1600,
        maximumRepathMs = 3000,
        maximumConsecutiveStalls = 3,
        maximumTraversalFailures = 2,
    },
    combat = {

        attackIntervalMs = 650,

        rangedIntervalMs = 560,

        burstCadenceMs = 120,

        burstMinRounds = 3,
        burstMaxRounds = 8,
        handgunBurstMax = 3,
        zombieBurstCap = 3,
        rangedRecoveryJitterMs = 400,

        aimHoldMs = 6000,
        aimWalkRangedRange = 14,

        pursuitRepathMs = 600,
        combatRepathDistance = 1.5,
        pathStallMs = 900,
        pathStartupGraceMs = 1600,

        meleeRange = 1.1,

        healthMultiplier = 1,

        standardHealth = 50,

        holdInReachMs = 2000,

        searchWindowMs = 45000,
        rangedStandoffMinimum = 6,
        rangedStandoffMaximum = 13,

        closeQuartersRange = 9,
        closeQuartersStandoff = 2.4,

        stairShotDistance = 3.5,

        flankDistance = 3.5,
        flankPhaseMs = 3200,

        readyGuardRange = 4,

        readyGuardRangeVersusGun = 1.6,

        sprintTriggerDistance = 4.5,
        sprintMs = 6400,
        sprintVersusGunMs = 8800,
        sprintCooldownMs = 9000,

        flankMinimumDistance = 5,
        runUpDistance = 2.5,

        weaponSwitchMs = 650,

        shoveDistance = 1.15,

        shoveKnockdownPercent = 20,
        targetMemoryMs = 9000,
        rangedWindupMs = 220,

        aimBaseMs = 300,
        aimWarmMs = 120,
        combatReadyMinimumMs = 24000,
        combatReadyMaximumMs = 27000,

        combatReadyMode = "default",
        combatReadyMixedPercent = 50,

        hitReactionPercent = 65,
        hitReactionMs = 450,
        hitReactionCooldownMs = 1100,
        rangedHitReactionCooldownMs = 1800,

        staggerDamage = 12,
        knockdownDamage = 30,
        headKnockdownPercent = 35,
        staggerMs = 800,
        staggerCooldownMs = 2500,
        knockdownCooldownMs = 6000,
        downedGetUpMinMs = 1400,
        downedGetUpJitterMs = 800,

        closingRunChancePercent = 80,
        closingRunMinimumDistance = 5.5,

        aimTraverseMs = 380,

        aimPrecisionMs = 90,
        aimMaximumMs = 750,

        meleeReadyMs = 220,

        meleeSpeedBonus = 0.16,
        meleeSkillLevel = 2,
        meleeKiteCrowd = 2,
        meleeKiteTiles = 2,
        meleeKiteStep = 1.6,
        meleeFootwork = true,
        meleeStepIn = 1.1,
        meleeStepArrive = 0.2,
        meleeFacing = true,
        meleeFacingMs = 1800,
        meleeBackpedal = 0.9,
        meleeBackpedalOver = 0.35,
        meleeBackpedalMinMs = 250,
        meleeGuardWalk = true,

        meleeWindupMs = 150,
        rangedRecoveryMs = 300,

        retreatSprintMs = 2500,

        gunshotGain = 2.4,
        meleeRecoveryMs = 680,
        reloadMs = 2300,
        reloadRackMs = 1350,
        internalReloadMs = 1200,
        internalReloadPerRoundMs = 950,

        jammingEnabled = true,
        jamChancePercent = 1,
        jamReactionMs = 500,
        jamRackMs = 1300,

        blockedLineTimeoutMs = 2500,

        breachGraceMs = 4000,

        multiHit = false,
        bulletPenetration = false,
        penetrationSquares = 3,

        rangedReachFactor = 1.0,

        handgunEffectiveRange = 12,
        shotgunEffectiveRange = 8,
        rifleEffectiveRange = 20,
        marksmanEffectiveRange = 30,
        aimRampMs = 5000,
        aimRampFloor = 0.5,
        aimRampGapMs = 15000,
        aimFarStart = 8,
        aimFarStep = 0.025,
        aimFarFloor = 0.65,
        aimMovingScale = 0.9,
        aimRunningScale = 0.78,

        playerFireReach = 22,
        marksmanPlayerFireReach = 34,

        kiteTriggerDistance = 8.0,
        kiteStepDistance = 5.5,
        kiteLegMs = 2600,
        kiteCooldownMs = 4200,

        coverLegMs = 3500,
        coverHurtFraction = 0.45,

        crossFloorTimeoutMs = 15000,
        unreachableCooldownMs = 1200,
        suppressionResetDistance = 4,
        maximumFailedAttacks = 8,

        climbHoldMs = 8000,
        climbQueueHoldMs = 2000,
        edgeGiveUpMs = 2500,

        leashGiveUpMs = 3000,
        leashClosingTiles = 0.8,

        leashReturnSlack = 1,

        leashRefuseMs = 10000,
        leashRefuseMargin = 1,
        leashSelfDefenceReach = 1.5,

        leashSortie = 4,
        leashGrudgeMs = 10000,

        approachStraightPercent = 40,
        approachLeftPercent = 30,
        approachArcMinimumDistance = 5,
        approachStraightDistance = 4,
        approachArcOffsetScale = 0.3,
        approachArcMinimumOffset = 1.5,
        approachArcMaximumOffset = 4,
        approachReplanDistance = 2.5,
        approachReplanMs = 1500,

        meleePressOpening = 0.5,
        meleePressRelease = 0.25,

        fenceStandoffMs = 1000,

        entranceSkipDistance = 3,
        entranceNearOpening = 1.5,
        entranceLegMs = 1500,

        rebuildMinimumMs = 600,

        humanMeleeBase = 9,
        humanMeleeExponent = 0.5,
        humanMeleeCap = 10.5,
        humanMeleeHeavyCap = 20,
        humanMeleeHeadPercent = 10,
        humanMeleeHeadScale = 1.8,
    },
    programs = {
        patrolRadius = 22,
        roamRadius = 32,
        huntRadius = 90,
        manhuntRadius = 250,
    },
    scavenging = {
        radius = 12,
        maximumSquares = 72,
    },
}

ProjectALife.BehaviorSettings = BehaviorSettings

return BehaviorSettings
