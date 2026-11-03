local function startmsg()
    print("==================================================")
    print("[True Weight] Loaded correctly!")
    print("[True Weight] A total of " .. tostring(TrueWeightTotal) .. " items have been rebalanced.")
    print("==================================================")
end

Events.OnGameStart.Add(startmsg)