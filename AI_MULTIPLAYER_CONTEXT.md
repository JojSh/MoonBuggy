# WebRTC Multiplayer Implementation Context - MoonBuggy

## Project Goal
Enable web browser multiplayer on itch.io while preserving ENet IP networking for native builds (Steam Deck/desktop).

## Architecture Implemented

### Dual-Mode Network System
- `GameSettings.NetworkMode` enum: `ENET` | `WEBRTC`
- Flag switchable for different export targets
- NetworkManager handles both modes with transparent API

### Modified Files
```
scripts/GameSettings.gd          - Added NetworkMode enum, network_mode variable (default ENET)
scripts/NetworkManager.gd        - Dual-mode logic, _join_game_relay(), _announce_player() RPC
scripts/NetworkLobby.gd          - UI adaptation for modes, late-joiner auto-start logic
scripts/RootNode.gd              - setup_network_screens(), delayed setup_network_player()
scripts/PlayerBuggy.gd           - Authority setup in setup_network_player() (lines 963-1017)
scripts/RelayServer.gd           - Minimal WebSocket relay (67 lines)
scenes/relay_server.tscn         - Relay server scene file
```

### Relay Server Configuration
- **Port**: 9080 (WebSocket)
- **Public URL**: `wss://semidomesticated-verona-oozily.ngrok-free.dev` (ngrok tunnel)
- **DEFAULT_RELAY_URL**: Set in `NetworkManager.gd` line 15
- **Function**: Pure message relay, no game logic (simplified from initial WebRTC signaling design)
- **Run**: Open `scenes/relay_server.tscn` in Godot, press F6

### Network Communication Flow
1. Web clients connect to relay via `WebSocketMultiplayerPeer.create_client(url)`
2. On connect: `_on_connected_to_server()` fires
3. Client registers self locally, calls `_announce_player.rpc(my_id, player_number)`
4. RPC broadcast to all peers (relay relays message)
5. Peers receive announcement, add to `connected_players` dictionary
6. `MultiplayerSynchronizer` nodes sync position/rotation/velocity between peers

### MultiplayerSynchronizer Setup
- **Location**: `scenes/PlayerBuggy.tscn` lines 57-69
- **Synced properties**: position, rotation, linear_velocity, angular_velocity
- **Replication mode**: 1 (on change)
- **Authority**: Set per-player in `PlayerBuggy.setup_network_player()`

## Problems Encountered & Solutions

### Issue 1: Relay Server Appearing as Player
**Symptom**: 
- Peer ID 1 (relay server) in `connected_players` 
- "Player 2" shown in lobby when only 1 human connected
- Authority set to peer 1 instead of real players

**Root Cause**: 
- Relay server runs same Godot project with NetworkManager autoload
- When clients call `_announce_player.rpc()`, relay receives and processes it
- Relay adds itself to its own `connected_players`
- `multiplayer.peer_connected` signal fires for relay (peer 1)

**Solution Applied**:
```gdscript
// NetworkManager.gd line 207-210
func _announce_player(peer_id, player_number):
    if my_id == 1: return  // If WE are relay, ignore all announcements
    if peer_id == 1: return  // If announcing peer is relay, ignore

// NetworkManager.gd line 128-131
func _on_player_connected(peer_id):
    if peer_id == 1 and is_webrtc_mode(): return  // Ignore relay connection event

// NetworkManager.gd line 157-159
func _on_connected_to_server():
    if my_id == 1: return  // Don't register if we're the relay
```

**Result**: Relay server successfully filtered, only real game clients in `connected_players`

---

### Issue 2: RPC Authority Violation
**Symptom**: 
- `start_network_game_for_all.rpc()` fails silently
- Game doesn't start when Player 1 presses "Start Game"
- No error in console

**Root Cause**: 
- NetworkLobby RPC marked as `@rpc("authority", "call_local", "reliable")`
- In relay mode, clients aren't "authority" (relay server peer 1 is)
- Non-authority peers can't call authority RPCs

**Solution Applied**:
```gdscript
// NetworkLobby.gd line 126
@rpc("any_peer", "call_local", "reliable")  // Changed from "authority"
func start_network_game_for_all():
```

**Result**: Any client can now trigger game start via RPC

---

### Issue 3: MultiplayerSynchronizer Authority Not Set
**Symptom**: 
- Browser console: `ERROR: Ignoring sync data from non-authority or for missing node`
- At: `scene_replication_interface.cpp:877`
- Players can't see each other's position/movement
- Rockets and explosions DO sync (via RPCs)

**Root Cause**: 
- `setup_network_player()` called immediately after game start
- `_announce_player` RPCs haven't propagated yet
- `connected_players` dictionary incomplete when setting authority
- Authority set to -1 (not found) or wrong peer

**Solution Applied**:
```gdscript
// RootNode.gd lines 582-594 in setup_network_screens()
// Moved from line 584 (immediate call) to after delay:
await get_tree().create_timer(0.3).timeout
print("[RootNode] Starting network player setup after announcement delay")
print("[RootNode] Connected players: ", NetworkManager.connected_players)
for player in list_of_players:
    player.setup_network_player()
```

**Debug Logs Added**:
```gdscript
// PlayerBuggy.gd line 997
print("[PlayerBuggy] Looking for peer with player_number ", player_number, " in connected_players: ", NetworkManager.connected_players)

// PlayerBuggy.gd line 1006
print("[PlayerBuggy] Set puppet authority to peer ", correct_peer_id, " for player ", player_number)
```

**Status**: Authority now sets correctly according to logs, but position sync still broken

---

### Issue 4: Late Joiners Break Everything
**Symptom**: 
- Player 1 starts game successfully
- Player 2 joins later, must manually click "Start Game"
- Cascade of errors in Player 1's console:
  ```
  ERROR: Node not found: "RootNode/NetworkLobby" (relative to "/root")
  ERROR: Failed to get path from RPC: RootNode/NetworkLobby
  ERROR: Invalid packet received. Requested node was not found.
  ```
- Player 2 sees same errors
- Both players stuck, can't see each other

**Root Cause**: 
- Player 1 starts game → NetworkLobby destroyed → enters gameplay
- Player 2 still in lobby, presses "Start Game"
- `start_network_game_for_all.rpc()` tries to call RPC on NetworkLobby
- Player 1 no longer has NetworkLobby node → RPC fails
- Synchronization breaks down

**Solution Attempted**:
```gdscript
// NetworkLobby.gd lines 160-173 in _on_connection_succeeded()
if NetworkManager.is_webrtc_mode():
    print("[NetworkLobby] Waiting 0.5s for peer announcements...")
    await get_tree().create_timer(0.5).timeout
    
    var player_count = NetworkManager.get_player_count()
    print("[NetworkLobby] After wait, player_count=", player_count, ", connected_players=", NetworkManager.connected_players)
    
    if player_count > 1:
        print("[NetworkLobby] Late joiner detected (", player_count, " players already connected), auto-starting game")
        emit_signal("start_network_game")  // Skip lobby, auto-join game
    else:
        print("[NetworkLobby] First player (player_count=", player_count, "), waiting for user to start game")
```

**Status**: NOT WORKING - Player 2 still needs to manually click "Start Game"

**Hypothesis**: 
- `_announce_player` RPC from Player 1 not reaching Player 2
- Player 2's `connected_players` only contains their own peer
- `get_player_count()` returns 1
- Auto-join logic doesn't trigger

**Debug Needed**: Player 2's browser console should show above print statements with actual values

---

### Issue 5: NetworkSync Node Path Invalid (HYPOTHESIS)
**Symptom**: 
- Console error: `Node not found: "RootNode/SinglePlayerCamera/PlayerBuggy1/NetworkSync"`
- Location: `scene/main/node.cpp:1908`
- Position/movement NOT syncing between players
- Players can see rockets/explosions (RPC-based) but not each other

**Analysis from Console Output**:
- Players successfully connect and detect each other
- Peer announcements working (peer 167291556 and 1107527623)
- NetworkSync node path error appears during gameplay
- Authority was being set correctly according to previous logs

**Hypothesis - Node Reparenting Breaks Cached Paths**:
1. PlayerBuggy nodes statically placed in scene at `PlayerScreenManager/PlayerContainer/PlayerBuggy1-4`
2. When scene loads, MultiplayerSynchronizer nodes enter scene tree
3. Godot's multiplayer system scans and **caches node paths**: `RootNode/PlayerScreenManager/PlayerContainer/PlayerBuggy1/NetworkSync`
4. During `setup_network_screens()`, players get reparented to `SinglePlayerCamera`
5. Cached paths become invalid: `RootNode/SinglePlayerCamera/PlayerBuggy1/NetworkSync` doesn't exist at expected location
6. MultiplayerSynchronizer can't find nodes, sync fails

**Attempted Fix (UNTESTED)**:
```gdscript
// RootNode.gd lines 552-593 - Rewritten setup_network_screens()
// Changed approach: DON'T reparent players

func setup_network_screens():
    # Clean up split screen containers
    for split_screen in $PlayerScreenManager/SplitScreens.get_children():
        split_screen.queue_free()
    
    var local_player_data = NetworkManager.get_local_player_data()
    var local_player_number = local_player_data.player_number if local_player_data else 1
    
    # Wait for RPC propagation
    await get_tree().create_timer(0.3).timeout
    
    # Setup network players WITHOUT reparenting (to preserve NetworkSync paths)
    for player in list_of_players:
        player.setup_network_player()
    
    # Camera management: enable local, disable remote
    for player in list_of_players:
        if player.player_number == local_player_number:
            player.get_node("ChaseCamPivot/ChaseCam").current = true
        else:
            # Disable all cameras for remote players
            player.get_node("ChaseCamPivot/ChaseCam").current = false
            player.get_node("SideCam").current = false
            player.get_node("FirstPersonCam").current = false
            player.get_node("ThirdPersonCam").current = false
            player.get_node("ChaseCamLocked").current = false
```

**Key Changes**:
1. Players stay in `PlayerScreenManager/PlayerContainer` permanently
2. NetworkSync paths remain: `RootNode/PlayerScreenManager/PlayerContainer/PlayerBuggy1/NetworkSync`
3. Only camera enable/disable changes (no node reparenting)
4. Removed camera disable code from `PlayerBuggy.gd` (now handled in RootNode)

**Expected Result if Hypothesis Correct**:
- NetworkSync path error should disappear
- Position/rotation/velocity should sync between players
- Players should see each other moving

**Status**: UNTESTED - Requires re-export and testing

---

---

### Issue 6: Player Number Assignment Race Condition (2025-12-02)
**Problem**: Player 2 registered as "player 1" because they picked player number before receiving Player 1's announcement
**Root Cause**: `_get_next_available_player_number()` checked local `connected_players` before announcements arrived
**Fix**: Added 0.2s delay in `NetworkManager._on_connected_to_server()` before assigning player number
**Result**: Players now get unique numbers ✅

### Issue 7: Extra Players Deleted on Game Start (2025-12-02)
**Problem**: `register_active_players()` deleted PlayerBuggy2-4 when only 1 player connected
**Result**: When Player 2 joined, their puppet didn't exist on Player 1's client
**Fix**: Keep all PlayerBuggy nodes alive in multiplayer mode (`register_active_players()` check)
**Result**: Late joiners now have puppets available ✅

### Issue 8: Node Reparenting Breaks NetworkSync (2025-11-30)
**Problem**: `setup_network_screens()` reparented players, invalidating MultiplayerSynchronizer paths
**Fix**: Players stay in `PlayerContainer`, camera management via enable/disable only
**Result**: NetworkSync paths remain valid ✅

### Issue 9: Authority Not Set During Lobby (2025-11-30)
**Problem**: Sync errors during lobby phase (before game starts)
**Fix**: `NetworkLobby._set_initial_network_authority()` sets authority immediately on connection
**Result**: Lobby sync errors eliminated ✅

### Issue 10: Late Joiners Don't Get Authority Set (2025-11-30)
**Problem**: `_on_network_player_joined()` didn't set NetworkSync authority for late-joiner puppets
**Fix**: Function now sets authority and calls `setup_network_player()` when players join mid-game
**Result**: Late joiners sync correctly ✅

---

## Current State (as of 2025-12-02)

### ✅ WORKING - Position Sync Fixed!
1. **Players can see each other moving** ✅
2. **Rockets/explosions sync** ✅
3. **Late joiners work** ✅
4. **Authority properly assigned** ✅
5. **Unique player numbers** ✅

### ❌ Known Issues
1. **Late joiner auto-start** - Player 2 must manually click "Start" (minor UX issue)
2. **Particle warnings** - WebGL compatibility renderer doesn't support sub-emitters (cosmetic)

## Key Solutions Applied
1. **0.2s delay before player number assignment** - prevents race condition
2. **Keep all PlayerBuggy nodes in multiplayer** - allows late joiners
3. **No player reparenting** - preserves MultiplayerSynchronizer paths
4. **Early authority setting** - NetworkSync authority set in lobby
5. **Late-joiner authority setup** - authority set when players join mid-game

---

## Current Investigation

### Next Steps
1. **Re-export and test** the no-reparenting fix
2. **Check console for**:
   - Does `Node not found: NetworkSync` error still appear?
   - Do players see each other moving?
   - Any new errors?
3. **If position sync works**: Investigate late-joiner auto-start separately
4. **If position sync fails**: Alternative approaches needed (MultiplayerSpawner, RemoteTransform, etc.)

### Debug Steps Needed
1. **Player 2 Console Check**: Verify late-joiner detection logs appear
2. **Both Consoles**: Confirm `[NetworkManager] _announce_player called` messages
3. **Verify Scene Tree**: Check if PlayerBuggy nodes exist on both clients
4. **Authority Verification**: Confirm `$NetworkSync.get_multiplayer_authority()` returns correct peer ID

---

## Code References

### NetworkManager Key Functions
```gdscript
// NetworkManager.gd line 62-95
func join_game(address, port):
    if current_network_mode == ENET:
        return _join_game_enet(address, port)
    else:
        return _join_game_relay(address)

func _join_game_relay(server_url_or_empty):
    var url = server_url_or_empty if !empty else DEFAULT_RELAY_URL
    var peer = WebSocketMultiplayerPeer.new()
    peer.create_client(url)
    multiplayer.multiplayer_peer = peer

// NetworkManager.gd line 152-173
func _on_connected_to_server():
    if is_webrtc_mode():
        var my_id = multiplayer.get_unique_id()
        if my_id == 1: return  // Don't register if we're relay
        
        var player_number = _get_next_available_player_number()
        connected_players[my_id] = {peer_id, player_number, name}
        _announce_player.rpc(my_id, player_number)

// NetworkManager.gd line 199-221
@rpc("any_peer", "call_remote", "reliable")
func _announce_player(peer_id, player_number):
    if my_id == 1: return  // Relay ignores
    if peer_id == 1: return  // Clients ignore relay
    
    if not connected_players.has(peer_id):
        connected_players[peer_id] = {peer_id, player_number, name}
        player_connected.emit(peer_id)
```

### PlayerBuggy Authority Setup
```gdscript
// PlayerBuggy.gd line 963-1017
func setup_network_player():
    if not NetworkManager.is_multiplayer_active():
        is_local_player = true
        return
    
    var local_player_data = NetworkManager.get_local_player_data()
    
    if local_player_data.player_number == player_number:
        // This IS the local player
        is_local_player = true
        network_player_id = local_player_data.peer_id
        $NetworkSync.set_multiplayer_authority(network_player_id)
    else:
        // This is a remote player (puppet)
        is_local_player = false
        
        // Find correct peer ID from connected_players
        for peer_data in NetworkManager.connected_players.values():
            if peer_data.player_number == player_number:
                $NetworkSync.set_multiplayer_authority(peer_data.peer_id)
                break
```

### Relay Server
```gdscript
// RelayServer.gd (simplified, 67 lines total)
const PORT = 9080
var connected_players = {}  // peer_id -> player_data

func _ready():
    var peer = WebSocketMultiplayerPeer.new()
    peer.create_server(PORT)
    multiplayer.multiplayer_peer = peer

func _on_peer_connected(id):
    print("Player ", id, " connected to relay")
    var player_number = _get_next_player_number()
    connected_players[id] = {peer_id: id, player_number, name}
    print("Assigned player number ", player_number, " to peer ", id)
    // Note: Clients handle their own peer announcements
```

---

## Testing Workflow

### Local Testing
1. Start relay server: Open `scenes/relay_server.tscn`, press F6 in Godot
2. Set `GameSettings.network_mode = GameSettings.NetworkMode.WEBRTC`
3. Export web build to test directory
4. Open 2+ browser tabs to `index.html`
5. Each tab: Click "Join", click "Start Game"
6. Check both browser consoles for debug logs

### itch.io Testing
1. Ensure `DEFAULT_RELAY_URL` points to ngrok URL
2. Export web build with WEBRTC mode enabled
3. Upload to itch.io
4. Test with 2 different browsers/devices
5. Check browser dev tools console for errors

---

## Next Steps

1. **Get Debug Logs from Player 2**:
   - Deploy latest build with debug logging
   - Have Player 2 join after Player 1 starts game
   - Check console for:
     ```
     [NetworkLobby] Waiting 0.5s for peer announcements...
     [NetworkLobby] After wait, player_count=?, connected_players=?
     [NetworkManager] _announce_player called: my_id=?, announcing peer=?, player_number=?
     ```

2. **If RPC Working**: Late-joiner should auto-start. If not, check `get_player_count()` value

3. **If RPC Not Working**: Investigate why `_announce_player` not propagating
   - Check relay server logs for RPC messages
   - Verify `@rpc("any_peer", "call_remote", "reliable")` configuration
   - Ensure relay isn't filtering the RPC

4. **Position Sync Investigation**:
   - Add logging in `_physics_process` to verify sync data being sent
   - Check if `$NetworkSync.get_multiplayer_authority()` matches expected peer
   - Verify MultiplayerSynchronizer root node path is correct
   - Test with simpler sync properties (position only)

---

## Important Notes

- **Don't export with debug logs to production** - remove print statements before final itch.io deployment
- **Relay server must stay running** - if relay crashes, all web clients disconnect
- **ngrok URL changes** - update `DEFAULT_RELAY_URL` if ngrok tunnel restarts
- **Browser cache** - hard refresh (Cmd+Shift+R) when testing new builds
- **MultiplayerSynchronizer authority** - must be set AFTER all peers announced themselves
- **0.3s delay** - critical for RPC propagation, may need adjustment based on network latency
