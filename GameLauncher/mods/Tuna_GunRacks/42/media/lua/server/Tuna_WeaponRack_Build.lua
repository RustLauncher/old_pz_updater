TunaWRBuild = TunaWRBuild or {}

-- params.facing arrives lowercase; getWallForFacing wants N/E/S/W and ignores its own self
function TunaWRBuild.NeedsWall(params)
    if not params or not params.square or not params.facing then return false end
    local dir = string.upper(params.facing)
    return ISMoveableSpriteProps.getWallForFacing(ISMoveableSpriteProps, params.square, dir) ~= nil
end
