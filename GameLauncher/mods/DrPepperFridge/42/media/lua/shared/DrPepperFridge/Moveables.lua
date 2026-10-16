-- Both halves deliberately retain native SpriteGridPos and pickup properties.
-- B42's multi-sprite pickup copies movableData for each part, and placement
-- restores it before our deferred distribution pass. No global pickup override
-- is needed; native rotation, collisions, weight and network ownership remain.
require 'DrPepperFridge/Core'
