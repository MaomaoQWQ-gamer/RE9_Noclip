-- Resident Evil 9 (RE9) Noclip
-- NOTE: This script uses the public SDK and should be safe to use. 
-- It mimics the logic of the known working noclip script.

if reframework:get_game_name() ~= "re9" then
    return
end

local cfg = {
    enabled = false,
    speed = 7.5,
    vertical_speed = 7.5,
    boost_mult = 3.0,
    slow_mult = 0.35,
    toggle_key = 0x71,
    mouse_steering = true,
    movement_yaw_offset = 180.0,
    character_yaw_offset = 180.0,
    anti_death_always = false,
    anti_death_grace_seconds = 10.0,
    godmode = true,
    block_game_over = true,
    suppress_fall_damage = true,
    suppress_fall_animations = true,
    aggressive_pose_kill = true,
    force_keep_ground = true,
    prevent_collision_shake = true,
    teleport_sync_rotation = true
}

local VK_W, VK_A, VK_S, VK_D = 0x57, 0x41, 0x53, 0x44
local VK_E, VK_Q, VK_C = 0x45, 0x51, 0x43
local VK_SHIFT, VK_CTRL = 0x10, 0x11
local EMPTY_HASH = 2180083513

local function clamp(v, min_v, max_v)
    if v < min_v then return min_v end
    if v > max_v then return max_v end
    return v
end

local function deg2rad(deg)
    return deg * (math.pi / 180.0)
end

local function vec3_add(a, b)
    return Vector3f.new(a.x + b.x, a.y + b.y, a.z + b.z)
end

local function vec3_scale(v, s)
    return Vector3f.new(v.x * s, v.y * s, v.z * s)
end

local function vec3_len(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function vec3_norm(v)
    local l = vec3_len(v)
    if l <= 0.00001 then return Vector3f.new(0, 0, 0) end
    return Vector3f.new(v.x / l, v.y / l, v.z / l)
end

local function quat_yaw(q)
    if not q then return 0.0 end
    local siny = 2.0 * (q.w * q.y + q.x * q.z)
    local cosy = 1.0 - 2.0 * (q.y * q.y + q.x * q.x)
    return (math.atan2 or math.atan)(siny, cosy)
end

local function quat_from_yaw(yaw)
    local h = yaw * 0.5
    return Vector4f.new(0.0, math.sin(h), 0.0, math.cos(h))
end

local function quat_rotate_vec(q, v)
    if not q or not v then return v end
    local ux, uy, uz, s = q.x, q.y, q.z, q.w
    local dot_uv = ux * v.x + uy * v.y + uz * v.z
    local dot_uu = ux * ux + uy * uy + uz * uz
    local cx = uy * v.z - uz * v.y
    local cy = uz * v.x - ux * v.z
    local cz = ux * v.y - uy * v.x
    return Vector3f.new(
        2.0 * dot_uv * ux + (s * s - dot_uu) * v.x + 2.0 * s * cx,
        2.0 * dot_uv * uy + (s * s - dot_uu) * v.y + 2.0 * s * cy,
        2.0 * dot_uv * uz + (s * s - dot_uu) * v.z + 2.0 * s * cz
    )
end

local function is_valid(obj)
    return obj ~= nil and (sdk.is_managed_object == nil or sdk.is_managed_object(obj))
end

local function get_singleton(type_name)
    local ok, inst = pcall(sdk.get_managed_singleton, type_name)
    if ok and inst then return inst end

    local ok_ns, ns_type = pcall(sdk.game_namespace, type_name)
    if ok_ns and ns_type then
        local ok2, inst2 = pcall(sdk.get_managed_singleton, ns_type)
        if ok2 and inst2 then return inst2 end
    end
    return nil
end

local function call_method(obj, candidates, ...)
    if not obj or not candidates then return nil, false end
    if type(candidates) == "string" then candidates = { candidates } end

    local args = { n = select("#", ...), ... }
    local unpack_args = table.unpack or unpack

    for _, name in ipairs(candidates) do
        local ok, res = pcall(function()
            return obj:call(name, unpack_args(args, 1, args.n))
        end)
        if ok and res ~= nil then return res, true end
    end

    local tdef = nil
    pcall(function() tdef = obj:get_type_definition() end)
    if tdef then
        local ok_m, methods = pcall(tdef.get_methods, tdef)
        if ok_m and methods then
            for _, candidate in ipairs(candidates) do
                local prefix = candidate:gsub("%(.*%)", "")
                for _, m in ipairs(methods) do
                    local m_name = m:get_name() or ""
                    if m_name == candidate or m_name:find("^" .. prefix) == 1 then
                        local ok_call, res = pcall(function()
                            return m:call(obj, unpack_args(args, 1, args.n))
                        end)
                        if ok_call and res ~= nil then return res, true end
                    end
                end
            end
        end
    end
    return nil, false
end

local function get_field(obj, candidates)
    if not obj or not candidates then return nil end
    if type(candidates) == "string" then candidates = { candidates } end

    for _, name in ipairs(candidates) do
        local variants = { name, "_" .. name, "_" .. name .. "_k__BackingField", "<" .. name .. ">k__BackingField" }
        for _, f in ipairs(variants) do
            local ok, val = pcall(obj.get_field, obj, f)
            if ok and val ~= nil then return val end
        end
    end
    return nil
end

local function set_field(obj, candidates, value)
    if not obj or not candidates then return false end
    if type(candidates) == "string" then candidates = { candidates } end

    for _, name in ipairs(candidates) do
        local variants = { name, "_" .. name, "_" .. name .. "_k__BackingField", "<" .. name .. ">k__BackingField" }
        for _, f in ipairs(variants) do
            local ok = pcall(obj.set_field, obj, f, value)
            if ok then return true end
        end
    end
    return false
end

local function find_method(type_name, candidate_names)
    if not type_name or not candidate_names then return nil end
    if type(candidate_names) == "string" then candidate_names = { candidate_names } end

    local tdef = sdk.find_type_definition(type_name)
    if not tdef then return nil end

    for _, name in ipairs(candidate_names) do
        local ok, m = pcall(tdef.get_method, tdef, name)
        if ok and m then return m end
    end

    local ok_m, methods = pcall(tdef.get_methods, tdef)
    if ok_m and methods then
        for _, candidate in ipairs(candidate_names) do
            local clean = candidate:gsub("%(.*%)", "")
            for _, m in ipairs(methods) do
                local actual = m:get_name() or ""
                if actual == candidate or actual:find("^" .. clean) == 1 then
                    return m
                end
            end
        end
    end
    return nil
end

local sigs = {
    player_context = {
        "getPlayerContextRefFast185379", "getPlayerContextRef185378",
        "getPlayerContextRefFast", "getPlayerContextRef",
        "get_PlayerContextFast185242", "get_PlayerContextFast",
        "get_CurrentPlayer", "PlayerContextFast"
    },
    get_pos = { "get_PositionFast232258", "get_PositionFast", "get_Position231767", "get_Position" },
    set_pos = {
        "set_PositionFast232259", "set_PositionFast(via.vec3)", "set_PositionFast",
        "set_Position231768", "set_Position(via.vec3)", "set_Position"
    },
    get_rot = { "get_Rotation231769", "get_Rotation" },
    set_rot = { "set_Rotation(via.Quaternion)", "set_Rotation" },
    get_updater = { "get_Updater232238", "get_Updater", "Updater" },
    get_cc = { "get_CharacterController", "getCharacterController", "get_MainCharacterController" },
    warp_cc = { "warp", "warp125040", "warp188755" },
    get_hp = { "get_HitPoint", "HitPoint", "_HitPoint" }
}

local t_transform = sdk.find_type_definition("via.Transform")
local m_transform_get_pos = t_transform and t_transform:get_method("get_Position")
local m_transform_set_pos = t_transform and t_transform:get_method("set_Position")
local m_transform_get_rot = t_transform and t_transform:get_method("get_Rotation")
local m_transform_set_rot = t_transform and t_transform:get_method("set_Rotation")

local state = {
    pos = nil,
    rot = nil,
    last_tick = os.clock(),
    status = "Ready.",
    context = nil,
    last_ctx_check = 0.0,
    is_ingame = false,
    anti_death_cooldown_until = 0.0,
    invincible_active = false,
    original_invincible = nil,
    saved_fall_checker = nil,
    hotkey_was_down = false
}

local function check_ingame_state()
    local gui_mgr = get_singleton("app.GuiManager")
    if gui_mgr then
        local in_game = get_field(gui_mgr, { "IsAvairableInGame", "IsAvailableInGame" })
        if in_game ~= nil then
            state.is_ingame = (in_game == true or in_game == 1)
            return state.is_ingame
        end
    end
    local char_mgr = get_singleton("app.CharacterManager")
    if char_mgr then
        local player = select(1, call_method(char_mgr, sigs.player_context))
        if is_valid(player) then
            state.is_ingame = true
            return true
        end
    end
    state.is_ingame = false
    return false
end

local function resolve_context()
    local char_mgr = get_singleton("app.CharacterManager")
        or get_singleton("app.PlayerManager")
        or get_singleton("app.PlayerContextManager")

    if not char_mgr then return nil end

    local player = select(1, call_method(char_mgr, sigs.player_context))
    if not is_valid(player) then
        player = get_field(char_mgr, { "PlayerContextFast", "CurrentPlayer" })
    end
    if not is_valid(player) then return nil end

    local transform = select(1, call_method(player, { "get_Transform231793", "get_Transform" }))
        or get_field(player, "Transform")

    local updater = select(1, call_method(player, sigs.get_updater))
        or get_field(player, "Updater")

    local cc = nil
    if updater then
        cc = select(1, call_method(updater, sigs.get_cc))
    end
    if not cc then
        cc = select(1, call_method(player, sigs.get_cc))
    end

    local env = updater and (get_field(updater, "EnvironmentProcessDriver") or select(1, call_method(updater, "get_EnvironmentProcessDriver")))
    local stance = updater and (get_field(updater, "PlayerStanceDriver") or select(1, call_method(updater, "get_PlayerStanceDriver")))

    return {
        player = player,
        transform = transform,
        updater = updater,
        character_controller = cc,
        env = env,
        stance = stance
    }
end

local function get_player_position(ctx)
    if not ctx then return nil end
    if ctx.transform and m_transform_get_pos then
        local ok, pos = pcall(m_transform_get_pos.call, m_transform_get_pos, ctx.transform)
        if ok and pos then return pos end
    end
    local pos = select(1, call_method(ctx.player, sigs.get_pos))
    if pos then return pos end
    if ctx.transform then
        pos = select(1, call_method(ctx.transform, { "get_Position" }))
        if pos then return pos end
    end
    return get_field(ctx.player, "PositionFast")
end

local function set_player_position(ctx, pos)
    if not ctx or not pos then return false end
    if ctx.character_controller then
        call_method(ctx.character_controller, sigs.warp_cc)
    end

    local ok_t = false
    if ctx.transform and m_transform_set_pos then
        local ok = pcall(m_transform_set_pos.call, m_transform_set_pos, ctx.transform, pos)
        ok_t = ok
    end
    if not ok_t and ctx.transform then
        local _, ok = call_method(ctx.transform, { "set_Position" }, pos)
        ok_t = ok
    end

    local _, ok_p = call_method(ctx.player, sigs.set_pos, pos)
    if ctx.character_controller then
        call_method(ctx.character_controller, sigs.warp_cc)
    end
    return ok_t or ok_p
end

local function get_player_rotation(ctx)
    if not ctx then return nil end
    if ctx.transform and m_transform_get_rot then
        local ok, rot = pcall(m_transform_get_rot.call, m_transform_get_rot, ctx.transform)
        if ok and rot then return rot end
    end
    local rot = select(1, call_method(ctx.player, sigs.get_rot))
    if rot then return rot end
    if ctx.transform then
        return select(1, call_method(ctx.transform, { "get_Rotation" }))
    end
    return nil
end

local function set_player_rotation(ctx, rot)
    if not ctx or not rot then return false end
    local ok_t = false
    if ctx.transform and m_transform_set_rot then
        local ok = pcall(m_transform_set_rot.call, m_transform_set_rot, ctx.transform, rot)
        ok_t = ok
    end
    if not ok_t and ctx.transform then
        local _, ok = call_method(ctx.transform, { "set_Rotation" }, rot)
        ok_t = ok
    end
    local _, ok_p = call_method(ctx.player, sigs.set_rot, rot)
    return ok_t or ok_p
end

local function get_camera_rot()
    local cam = sdk.get_primary_camera()
    if not cam then return nil end

    local matrix = select(1, call_method(cam, "get_WorldMatrix"))
    if matrix and matrix.to_quat then
        local ok, q = pcall(matrix.to_quat, matrix)
        if ok and q then return q end
    end

    local go = select(1, call_method(cam, "get_GameObject"))
    local transform = go and select(1, call_method(go, "get_Transform"))
    if transform then
        return select(1, call_method(transform, "get_Rotation"))
    end
    return nil
end

local function get_camera_pos()
    local cam = sdk.get_primary_camera()
    if not cam then return nil end

    local matrix = select(1, call_method(cam, "get_WorldMatrix"))
    if matrix and matrix[3] then
        local row = matrix[3]
        return Vector3f.new(row.x, row.y, row.z)
    end

    local go = select(1, call_method(cam, "get_GameObject"))
    local transform = go and select(1, call_method(go, "get_Transform"))
    if transform then
        return select(1, call_method(transform, "get_Position"))
    end
    return nil
end

local function is_anti_death_needed()
    if not state.is_ingame then return false end
    if cfg.anti_death_always or cfg.enabled then return true end
    return (state.anti_death_cooldown_until - os.clock()) > 0.0
end

local function apply_health_protection(ctx, enable)
    if not ctx or not is_valid(ctx.player) then return end
    local hp = select(1, call_method(ctx.player, sigs.get_hp)) or get_field(ctx.player, "HitPoint")
    if not hp then return end

    if enable and cfg.godmode then
        if not state.invincible_active then
            state.original_invincible = select(1, call_method(hp, { "get_Invincible" }))
            state.invincible_active = true
        end
        call_method(hp, { "set_Invincible" }, true)
        local max_hp = select(1, call_method(hp, { "get_CurrentMaximumHitPoint" }))
        if max_hp and max_hp > 0 then
            call_method(hp, { "resetHitPoint" }, max_hp)
        end
    elseif not enable and state.invincible_active then
        if state.original_invincible ~= nil then
            call_method(hp, { "set_Invincible" }, state.original_invincible)
        end
        state.invincible_active = false
        state.original_invincible = nil
    end
end

local function bypass_airborne_action_lock(ctx)
    if not ctx or not ctx.updater then return end
    local updater = ctx.updater

    local action_unit = select(1, call_method(updater, { "get_ActionBlackboardUnit()", "get_ActionBlackboardUnit" }))
    if action_unit then
        call_method(action_unit, { "requestEndCurrentAction()", "requestEndCurrentAction" })
        local action_state = get_field(action_unit, { "ActionState", "_ActionState" })
        if action_state then
            call_method(action_state, { "set_ActionEnd" }, true)
        end
    end

    local common = get_field(ctx.player, "Common") or select(1, call_method(ctx.player, "get_Common232225"))
    if common then
        set_field(common, "FallType", 0)
        set_field(common, "IsDamageContinueState", false)
        set_field(common, "IsFastGameOver", false)
        set_field(common, "IsTerrainAction", false)
    end

    set_field(updater, "RequestedFallingHash", EMPTY_HASH)
    set_field(updater, "RequestedLandingHash", EMPTY_HASH)
    set_field(updater, "IsDeadTrigger", false)
    set_field(updater, "IsOtherGameOver", false)

    local anim_fall = get_field(updater, "AnimFallGroundChecker")
    if anim_fall then
        set_field(anim_fall, "IsAdjust", false)
        set_field(anim_fall, "InputDeltaMove", Vector3f.new(0, 0, 0))
        call_method(anim_fall, "endAnimation148413")
    end

    if cfg.aggressive_pose_kill then
        if not state.saved_fall_checker then
            state.saved_fall_checker = get_field(updater, "AnimFallGroundChecker")
        end
        set_field(updater, "AnimFallGroundChecker", nil)
        call_method(updater, { "offAnimation208870", "offAnimation" })
    end

    local env = ctx.env or get_field(updater, "EnvironmentProcessDriver") or select(1, call_method(updater, "get_EnvironmentProcessDriver"))
    if env then
        ctx.env = env
        call_method(env, { "preventFall188776", "preventFall" })
        call_method(env, { "clearLandingToFallLoopCheck195507", "clearLandingToFallLoopCheck" })
        call_method(env, { "setLandingAction195499", "setLandingAction" }, false)
        call_method(env, { "stopFreeFallCtrl188782", "stopFreeFallCtrl" })

        if cfg.force_keep_ground then
            set_field(env, "IsKeepGround", true)
            set_field(env, "IsPrevKeepGround", true)
            set_field(env, "IsFallingIntoCrack", false)
            set_field(env, "IsFoundCrack", false)
            set_field(env, "FallProcessID", nil)
        end

        set_field(env, "FallDamage", 0)
        set_field(env, "FallHeight", 0.0)
        set_field(env, "PrevFallHeight", 0.0)
        set_field(env, "HeightKeepGround", 100000.0)
        set_field(env, "HeightPreventFall", 100000.0)
        set_field(env, "IsDisableGravityUntilMotionEnd", true)

        local freefall = get_field(env, "FreeFallCtrl")
        if freefall then
            set_field(freefall, "IsActive", false)
            set_field(freefall, "IsRise", false)
            set_field(freefall, "FrameGravity", 0.0)
            set_field(freefall, "InitialFrameSpeed", Vector3f.new(0.0, 0.0, 0.0))
            set_field(freefall, "MaxFallFrameSpeed", 0.0)
        end
    end

    local stance = ctx.stance or get_field(updater, "PlayerStanceDriver") or select(1, call_method(updater, "get_PlayerStanceDriver"))
    if stance then
        ctx.stance = stance
        call_method(stance, { "continueHandDown204352", "continueHandDown" })
        call_method(stance, { "updateHandDown204345", "updateHandDown" })
        call_method(stance, { "updateHandDownMotion204354", "updateHandDownMotion" })
        call_method(stance, { "updateHandDownInternal204346", "updateHandDownInternal" })
        call_method(stance, { "updateTempHandDown204350", "updateTempHandDown" })
    end
end

local function restore_ground_and_pose_system(ctx)
    if not ctx or not ctx.updater then return end
    if state.saved_fall_checker then
        set_field(ctx.updater, "AnimFallGroundChecker", state.saved_fall_checker)
        state.saved_fall_checker = nil
    end
end

local hooks_installed = false

local function register_guard_hook(type_name, candidates, condition_fn)
    local method = find_method(type_name, candidates)
    if not method then return false end

    pcall(sdk.hook, method,
        function(_)
            if condition_fn and condition_fn() then
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
            return sdk.PreHookResult.CALL_ORIGINAL
        end,
        function(retval) return retval end
    )
    return true
end

local function install_safety_hooks()
    if hooks_installed then return end
    hooks_installed = true

    local should_block_death = function() return cfg.block_game_over and is_anti_death_needed() end
    local should_block_fall = function() return state.is_ingame and cfg.enabled and cfg.suppress_fall_animations end

    register_guard_hook("app.PlayerUpdaterBase", { "updateDeadRequest208838", "updateDeadRequest" }, should_block_death)
    register_guard_hook("app.PlayerUpdaterBase", { "onDead208840", "onDead" }, should_block_death)
    register_guard_hook("app.PlayerUpdaterBase", { "checkExecuteDeadActionOnDead208841", "checkExecuteDeadActionOnDead" }, should_block_death)
    register_guard_hook("app.PlayerUpdaterBase", { "execSafeProcFallLimit208946", "execSafeProcFallLimit" }, should_block_death)
    register_guard_hook("app.CharacterManager", { "requestGameOver185454", "requestGameOver" }, should_block_death)
    register_guard_hook("app.GameOverManager", { "requestGameOver249161", "requestGameOver" }, should_block_death)
    register_guard_hook("app.GameOverManager", { "transitPhase249163", "transitPhase" }, should_block_death)
    register_guard_hook("app.PlayerDeadBodyDriver", { "updateCheckDeadSpace204109", "updateCheckDeadSpace" }, should_block_death)

    register_guard_hook("app.PlayerUpdaterBase", { "set_RequestedFallingHash208544", "set_RequestedFallingHash" }, should_block_fall)
    register_guard_hook("app.PlayerUpdaterBase", { "set_RequestedLandingHash208546", "set_RequestedLandingHash" }, should_block_fall)
    register_guard_hook("app.PlayerEnvironmentProcessDriver", { "setLandingAction195499", "setLandingAction" }, should_block_fall)
    register_guard_hook("app.PlayerEnvironmentProcessDriver", { "onUpdateScanPhase195495", "onUpdateScanPhase" }, should_block_fall)
    register_guard_hook("app.PlayerEnvironmentProcessDriver", { "landingPlayerProcess195496", "landingPlayerProcess" }, should_block_fall)
    register_guard_hook("app.PlayerEnvironmentProcessDriver", { "lateUpdateAdditionalAction195497", "lateUpdateAdditionalAction" }, should_block_fall)
    register_guard_hook("app.PlayerEnvironmentProcessDriver", { "isPreventFall195500", "isPreventFall" }, should_block_fall)
    register_guard_hook("app.PlayerEnvironmentProcessDriver", { "isSkipPreventFall195502", "isSkipPreventFall" }, should_block_fall)
    register_guard_hook("app.PlayerEnvironmentProcessDriver", { "onActionLocked195506", "onActionLocked" }, should_block_fall)
    register_guard_hook("app.PlayerEnvironmentProcessDriver", { "updateClimbStartType195503", "updateClimbStartType" }, should_block_fall)
    register_guard_hook("app.PlayerEnvironmentProcessDriver", { "checkClimbStartType195504", "checkClimbStartType" }, should_block_fall)
    register_guard_hook("app.PlayerEnvironmentProcessDriver", { "checkFallLengthRequestedFallingHash195498", "checkFallLengthRequestedFallingHash" }, should_block_fall)
    register_guard_hook("app.PlayerEnvironmentProcessDriver", { "checkSafeAreaFallEnd195501", "checkSafeAreaFallEnd" }, should_block_fall)
    register_guard_hook("anim.AnimFallGroundChecker", { "updateAnimation148414", "updateAnimation" }, should_block_fall)
    register_guard_hook("anim.AnimFallGroundChecker", { "checkFallGround148415", "checkFallGround" }, should_block_fall)
    register_guard_hook("anim.AnimFallGroundChecker", { "checkFallGroundCore148416", "checkFallGroundCore" }, should_block_fall)
    register_guard_hook("app.EnvironmentProcessDriver", { "updateFallInfo188758", "updateFallInfo" }, should_block_fall)
    register_guard_hook("app.EnvironmentProcessDriver", { "detectGroundForAutoFallAction188780", "detectGroundForAutoFallAction" }, should_block_fall)
    register_guard_hook("app.EnvironmentProcessDriver", { "updateClimbStep188752", "updateClimbStep" }, function()
        return should_block_fall() and cfg.prevent_collision_shake
    end)

    register_guard_hook("app.PlayerStanceDriver", { "updateHandUpMotion204355", "updateHandUpMotion" }, should_block_fall)
    register_guard_hook("app.PlayerStanceDriver", { "isEnableHandUpChangeAction204349", "isEnableHandUpChangeAction" }, should_block_fall)
    register_guard_hook("app.PlayerStanceDriver", { "onUpdateActPhase204331", "onUpdateActPhase" }, should_block_fall)
    register_guard_hook("app.PlayerStanceDriver", { "updateStance204333", "updateStance" }, should_block_fall)
    register_guard_hook("app.PlayerStanceDriver", { "updateStanceState204332", "updateStanceState" }, should_block_fall)
    register_guard_hook("app.PlayerStanceDriver", { "updateStanceTrigger204335", "updateStanceTrigger" }, should_block_fall)
    register_guard_hook("app.PlayerStanceDriver", { "updateStanceBankType204336", "updateStanceBankType" }, should_block_fall)
end

local function set_noclip(enable)
    if enable == cfg.enabled then return end

    if enable and not state.is_ingame then
        state.status = "Blocked: Not in-game."
        return
    end

    cfg.enabled = enable
    if not enable then
        state.anti_death_cooldown_until = os.clock() + cfg.anti_death_grace_seconds
        restore_ground_and_pose_system(state.context)
        if not is_anti_death_needed() then
            apply_health_protection(state.context, false)
        end
        state.status = "NoClip disabled."
        return
    end

    state.context = resolve_context()
    if not state.context then
        state.status = "Failed to resolve player context."
        return
    end

    state.pos = get_player_position(state.context)
    state.rot = get_player_rotation(state.context)
    apply_health_protection(state.context, true)
    bypass_airborne_action_lock(state.context)
    state.status = "NoClip active."
end

local function teleport_to_camera()
    if not state.is_ingame or not state.context then
        state.status = "Teleport failed: No active player."
        return
    end

    local cam_pos = get_camera_pos()
    if not cam_pos then return end

    if set_player_position(state.context, cam_pos) then
        state.pos = cam_pos
        if cfg.teleport_sync_rotation then
            local cam_rot = get_camera_rot()
            if cam_rot then
                local yaw = quat_yaw(cam_rot) + deg2rad(cfg.character_yaw_offset)
                local new_rot = quat_from_yaw(yaw)
                set_player_rotation(state.context, new_rot)
                state.rot = new_rot
            end
        end
        state.status = "Teleported to camera."
    end
end

re.on_pre_application_entry("UpdateBehavior", function()
    install_safety_hooks()
    check_ingame_state()

    if state.is_ingame and cfg.enabled and state.context then
        bypass_airborne_action_lock(state.context)
    end
end)

re.on_frame(function()
    install_safety_hooks()
    check_ingame_state()

    local now = os.clock()
    local dt = clamp(now - state.last_tick, 0.0, 0.25)
    state.last_tick = now

    local toggle_down = reframework:is_key_down(cfg.toggle_key)
    if toggle_down and not state.hotkey_was_down then
        set_noclip(not cfg.enabled)
    end
    state.hotkey_was_down = toggle_down

    if not state.is_ingame then
        if cfg.enabled then set_noclip(false) end
        state.status = "Waiting for game session..."
        return
    end

    if not state.context or (now - state.last_ctx_check) > 1.0 then
        state.last_ctx_check = now
        state.context = resolve_context()
    end

    if is_anti_death_needed() then
        apply_health_protection(state.context, true)
    elseif state.invincible_active then
        apply_health_protection(state.context, false)
    end

    if not cfg.enabled then
        if state.context then
            state.pos = get_player_position(state.context)
            state.rot = get_player_rotation(state.context)
        end
        return
    end

    if not state.context then return end

    bypass_airborne_action_lock(state.context)

    if not state.pos then state.pos = get_player_position(state.context) end
    if not state.rot then state.rot = get_player_rotation(state.context) end
    if not state.pos then return end

    local cam_rot = get_camera_rot()
    if cfg.mouse_steering and cam_rot then
        state.rot = cam_rot
    end

    local mx = (reframework:is_key_down(VK_A) and 1.0 or 0.0) - (reframework:is_key_down(VK_D) and 1.0 or 0.0)
    local mz = (reframework:is_key_down(VK_W) and 1.0 or 0.0) - (reframework:is_key_down(VK_S) and 1.0 or 0.0)
    local down_key = (reframework:is_key_down(VK_Q) or reframework:is_key_down(VK_C)) and 1.0 or 0.0
    local my = (reframework:is_key_down(VK_E) and 1.0 or 0.0) - down_key

    local spd = cfg.speed
    local vspd = cfg.vertical_speed
    if reframework:is_key_down(VK_SHIFT) then
        spd = spd * cfg.boost_mult
        vspd = vspd * cfg.boost_mult
    elseif reframework:is_key_down(VK_CTRL) then
        spd = spd * cfg.slow_mult
        vspd = vspd * cfg.slow_mult
    end

    local move_offset = cfg.mouse_steering and cfg.movement_yaw_offset or 0.0
    local move_yaw = quat_yaw(state.rot) + deg2rad(move_offset)
    local move_rot = quat_from_yaw(move_yaw)

    local move_mag = math.sqrt(mx * mx + mz * mz)
    if move_mag > 1.0 then
        mx = mx / move_mag
        mz = mz / move_mag
        move_mag = 1.0
    end

    local local_dir = Vector3f.new(mx, 0.0, mz)
    local horiz = quat_rotate_vec(move_rot, local_dir)
    horiz.y = 0.0
    if vec3_len(horiz) > 0.0001 then
        horiz = vec3_norm(horiz)
    end

    local delta_h = vec3_scale(horiz, spd * dt * move_mag)
    local delta_v = Vector3f.new(0.0, my * vspd * dt, 0.0)
    local delta = vec3_add(delta_h, delta_v)

    if vec3_len(delta) > 0.000001 then
        state.pos = vec3_add(state.pos, delta)
    end

    set_player_position(state.context, state.pos)
    if cfg.mouse_steering and state.rot then
        local sync_yaw = quat_yaw(state.rot) + deg2rad(cfg.character_yaw_offset)
        set_player_rotation(state.context, quat_from_yaw(sync_yaw))
    end
end)

re.on_draw_ui(function()
    if not imgui.tree_node("RE9 NoClip PC") then return end

    local changed, new_val

    changed, new_val = imgui.checkbox("Enable NoClip (F2)", cfg.enabled)
    if changed then set_noclip(new_val) end

    changed, cfg.anti_death_always = imgui.checkbox("Always Enable Anti-Death / Godmode", cfg.anti_death_always)

    imgui.spacing()
    imgui.text_colored("--- Controls (Keyboard & Mouse) ---", 0xFF88FFFF)
    imgui.text("Toggle: F2 | Move: W/A/S/D | Up: E | Down: Q/C")
    imgui.text("Sprint: Shift | Slow/Precision: Ctrl")

    imgui.spacing()
    if imgui.collapsing_header("Speed & Steering") then
        changed, cfg.speed = imgui.drag_float("Horizontal Speed", cfg.speed, 0.1, 0.1, 100.0, "%.2f")
        changed, cfg.vertical_speed = imgui.drag_float("Vertical Speed", cfg.vertical_speed, 0.1, 0.1, 100.0, "%.2f")
        changed, cfg.boost_mult = imgui.drag_float("Sprint Boost (Shift)", cfg.boost_mult, 0.1, 1.0, 20.0, "%.1fx")
        changed, cfg.slow_mult = imgui.drag_float("Slow Mode (Ctrl)", cfg.slow_mult, 0.05, 0.05, 1.0, "%.2fx")
        changed, cfg.mouse_steering = imgui.checkbox("Mouse Steering (Sync Camera Direction)", cfg.mouse_steering)
        if cfg.mouse_steering then
            changed, cfg.character_yaw_offset = imgui.drag_float("Character Facing Offset", cfg.character_yaw_offset, 1.0, -180.0, 180.0, "%.0f deg")
        end
    end

    if imgui.collapsing_header("Camera Actions") then
        changed, cfg.teleport_sync_rotation = imgui.checkbox("Sync Yaw on Teleport", cfg.teleport_sync_rotation)
        if imgui.button("Teleport Character to Camera") then
            teleport_to_camera()
        end
    end

    if imgui.collapsing_header("Physics & Protections") then
        changed, cfg.force_keep_ground = imgui.checkbox("Force Keep Ground (Fix Mouse Lock)", cfg.force_keep_ground)
        changed, cfg.aggressive_pose_kill = imgui.checkbox("Aggressive Pose Kill (Kill Fall Stance)", cfg.aggressive_pose_kill)
        changed, cfg.godmode = imgui.checkbox("Invincibility / Godmode", cfg.godmode)
        changed, cfg.suppress_fall_damage = imgui.checkbox("Nullify Fall Damage", cfg.suppress_fall_damage)
        changed, cfg.suppress_fall_animations = imgui.checkbox("Suppress Fall Glitches", cfg.suppress_fall_animations)
        changed, cfg.prevent_collision_shake = imgui.checkbox("Prevent Collision Shake", cfg.prevent_collision_shake)
        changed, cfg.anti_death_grace_seconds = imgui.drag_float("Anti-Death Grace Cooldown", cfg.anti_death_grace_seconds, 0.5, 1.0, 30.0, "%.1fs")
    end

    imgui.spacing()
    imgui.separator()

    if state.pos then
        imgui.text(string.format("Position: X %.2f | Y %.2f | Z %.2f", state.pos.x, state.pos.y, state.pos.z))
    end
    imgui.text("Session: " .. (state.is_ingame and "In-Game" or "Menu / Loading"))
    imgui.text("Status: " .. tostring(state.status))

    imgui.tree_pop()
end)