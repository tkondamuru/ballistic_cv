/**
 * @file hub_core.js
 * @description Centralized Core Engine for Ballistic CV Web Game Suite.
 * 
 * Manages:
 * 1. Global Hardware & Spatial Calibration (Vector Offset Line Dragging, Pin Margins, Marker Sizing).
 * 2. WebSocket Real-time Impact Event Stream (`wss://mcp.agility-maint.net`).
 * 3. Modular Game Lifecycle (Dynamic Mounting, Hot-swapping via Drawer Menu, Stats Dispatching).
 * 4. High-Contrast Light Mode Rendering (Neon Contact Circles + Expanding Shockwave Ripples).
 */

import BugSquashGame from '../games/bug_squash.js';
import BalloonPopGame from '../games/balloon_pop.js';
import BreakoutGame from '../games/breakout.js';
import BullseyeGame from '../games/bullseye.js';
import ColorPaintGame from '../games/color_paint.js';
import MathBlasterGame from '../games/math_blaster.js';

export class ThudHubCore {
  constructor() {
    this.canvas = document.getElementById('canvas');
    this.ctx = this.canvas.getContext('2d');

    // UI Controls & Badges
    this.statusDot = document.getElementById('statusDot');
    this.statusBadge = document.getElementById('statusBadge');
    this.calibBtn = document.getElementById('calibBtn');
    this.calibBanner = document.getElementById('calibBanner');
    this.offsetXInput = document.getElementById('offsetX');
    this.offsetYInput = document.getElementById('offsetY');
    this.marginSlider = document.getElementById('marginSlider');
    this.pinSizeSlider = document.getElementById('pinSizeSlider');
    
    this.marginVal = document.getElementById('marginVal');
    this.pinSizeVal = document.getElementById('pinSizeVal');

    // WebSocket Settings Popover Elements
    this.wsUrlInput = document.getElementById('wsUrl');
    this.roomInput = document.getElementById('roomInput');
    this.connectBtn = document.getElementById('connectBtn');
    this.wsToggleBtn = document.getElementById('wsToggleBtn');
    this.wsPopover = document.getElementById('wsPopover');

    // Dynamic Game Options Placeholder & HUD
    this.gameOptionsContainer = document.getElementById('gameOptionsContainer');
    this.hudStatsText = document.getElementById('hudStatsText');
    this.victoryBadge = document.getElementById('victoryBadge');
    this.victoryText = document.getElementById('victoryText');
    this.currentGameTitle = document.getElementById('currentGameTitle');

    // Quad Alignment Corner Pins (TL, TR, BL, BR)
    this.cornerTL = document.getElementById('corner-tl');
    this.cornerTR = document.getElementById('corner-tr');
    this.cornerBL = document.getElementById('corner-bl');
    this.cornerBR = document.getElementById('corner-br');

    // Games Registry Map
    this.games = {
      'bug_squash': new BugSquashGame(),
      'balloon_pop': new BalloonPopGame(),
      'breakout': new BreakoutGame(),
      'bullseye': new BullseyeGame(),
      'color_paint': new ColorPaintGame(),
      'math_blaster': new MathBlasterGame()
    };

    this.activeGame = this.games['bug_squash'];

    // WebSocket Connection State
    this.socket = null;

    // Spatial Vector Calibration State
    this.isCalibrating = false;
    this.lastThudPoint = null;
    this.calibTargetPoint = null;
    this.isDraggingCalib = false;

    // Visual Ripples & Contact Point Effects
    this.ripples = [];

    // Frame Loop Delta Clock
    this.lastFrameTime = performance.now();
  }

  /**
   * Initializes settings, registers event listeners, sizes canvas, and starts main animation loop.
   */
  init() {
    this.loadSavedSettings();
    this.setupEventListeners();
    this.resizeCanvas();
    this.updateCornerPins();

    // Initialize initial active game module and render its specific controls
    this.activeGame.init(this.canvas, this.getMargin());
    this.renderGameOptions();
    this.updateHudStats();

    // Start 60 FPS animation loop
    requestAnimationFrame((t) => this.loop(t));
  }

  getMargin() {
    return parseInt(this.marginSlider.value) || 24;
  }

  getPinSize() {
    return parseInt(this.pinSizeSlider ? this.pinSizeSlider.value : 36) || 36;
  }

  getOffsetX() {
    return parseInt(this.offsetXInput.value) || 0;
  }

  getOffsetY() {
    return parseInt(this.offsetYInput.value) || 0;
  }

  /**
   * Adjusts horizontal/vertical calibration offsets via step buttons (- / +).
   */
  stepOffset(axis, delta) {
    if (axis === 'X') {
      const val = Math.max(-200, Math.min(200, this.getOffsetX() + delta));
      this.offsetXInput.value = val;
    } else if (axis === 'Y') {
      const val = Math.max(-200, Math.min(200, this.getOffsetY() + delta));
      this.offsetYInput.value = val;
    }
    this.saveSettings();
  }

  resizeCanvas() {
    this.canvas.width = window.innerWidth;
    this.canvas.height = window.innerHeight;
    this.updateCornerPins();
  }

  /**
   * Positions and scales the 4 corner alignment pins (TL, TR, BL, BR) according to margin and pin size settings.
   */
  updateCornerPins() {
    const margin = this.getMargin();
    const pinSize = this.getPinSize();

    if (this.marginVal) this.marginVal.innerText = `${margin}px`;
    if (this.pinSizeVal) this.pinSizeVal.innerText = `${pinSize}px`;

    const pins = [this.cornerTL, this.cornerTR, this.cornerBL, this.cornerBR].filter(Boolean);
    pins.forEach(pin => {
      pin.style.width = `${pinSize}px`;
      pin.style.height = `${pinSize}px`;
      pin.style.fontSize = `${Math.max(9, Math.round(pinSize * 0.32))}px`;
    });

    if (this.cornerTL) { this.cornerTL.style.top = `${margin}px`; this.cornerTL.style.left = `${margin}px`; }
    if (this.cornerTR) { this.cornerTR.style.top = `${margin}px`; this.cornerTR.style.right = `${margin}px`; }
    if (this.cornerBL) { this.cornerBL.style.bottom = `${margin}px`; this.cornerBL.style.left = `${margin}px`; }
    if (this.cornerBR) { this.cornerBR.style.bottom = `${margin}px`; this.cornerBR.style.right = `${margin}px`; }
  }

  /**
   * Dynamically renders game-specific UI options inside #gameOptionsContainer slot.
   */
  renderGameOptions() {
    if (!this.gameOptionsContainer) return;
    this.gameOptionsContainer.innerHTML = '';
    if (this.activeGame && this.activeGame.renderOptions) {
      this.activeGame.renderOptions(this.gameOptionsContainer);
    }
  }

  loadSavedSettings() {
    if (localStorage.getItem('thud_off_x') !== null) this.offsetXInput.value = localStorage.getItem('thud_off_x');
    if (localStorage.getItem('thud_off_y') !== null) this.offsetYInput.value = localStorage.getItem('thud_off_y');
    if (localStorage.getItem('thud_ws_url') !== null) this.wsUrlInput.value = localStorage.getItem('thud_ws_url');
    if (localStorage.getItem('thud_room') !== null) this.roomInput.value = localStorage.getItem('thud_room');
    if (localStorage.getItem('thud_pin_margin') !== null) this.marginSlider.value = localStorage.getItem('thud_pin_margin');
    if (localStorage.getItem('thud_pin_size') !== null && this.pinSizeSlider) this.pinSizeSlider.value = localStorage.getItem('thud_pin_size');
  }

  saveSettings() {
    localStorage.setItem('thud_off_x', this.offsetXInput.value);
    localStorage.setItem('thud_off_y', this.offsetYInput.value);
    localStorage.setItem('thud_ws_url', this.wsUrlInput.value);
    localStorage.setItem('thud_room', this.roomInput.value);
    localStorage.setItem('thud_pin_margin', this.marginSlider.value);
    if (this.pinSizeSlider) localStorage.setItem('thud_pin_size', this.pinSizeSlider.value);
  }

  setupEventListeners() {
    window.addEventListener('resize', () => this.resizeCanvas());

    [this.offsetXInput, this.offsetYInput, this.wsUrlInput, this.roomInput]
      .filter(Boolean)
      .forEach(el => el.addEventListener('change', () => this.saveSettings()));

    if (this.marginSlider) {
      this.marginSlider.addEventListener('input', () => {
        this.saveSettings();
        this.updateCornerPins();
      });
    }

    if (this.pinSizeSlider) {
      this.pinSizeSlider.addEventListener('input', () => {
        this.saveSettings();
        this.updateCornerPins();
      });
    }

    // Step offset buttons (- / +)
    document.querySelectorAll('[data-step-axis]').forEach(btn => {
      btn.addEventListener('click', (e) => {
        const axis = e.currentTarget.getAttribute('data-step-axis');
        const delta = parseInt(e.currentTarget.getAttribute('data-step-delta')) || 0;
        this.stepOffset(axis, delta);
      });
    });

    // WebSocket Popover Toggle (via button or status dot badge)
    const toggleWs = (e) => {
      e.stopPropagation();
      if (this.wsPopover) this.wsPopover.classList.toggle('open');
    };

    if (this.wsToggleBtn) this.wsToggleBtn.addEventListener('click', toggleWs);
    if (this.statusBadge) this.statusBadge.addEventListener('click', toggleWs);

    document.addEventListener('click', (e) => {
      if (this.wsPopover && this.wsPopover.classList.contains('open')) {
        const isClickInside = this.wsPopover.contains(e.target) ||
                              (this.wsToggleBtn && this.wsToggleBtn.contains(e.target)) ||
                              (this.statusBadge && this.statusBadge.contains(e.target));
        if (!isClickInside) {
          this.wsPopover.classList.remove('open');
        }
      }
    });

    if (this.connectBtn) {
      this.connectBtn.addEventListener('click', () => {
        this.connectWebSocket();
        if (this.wsPopover) this.wsPopover.classList.remove('open');
      });
    }

    this.calibBtn.addEventListener('click', () => this.toggleCalibrationMode());

    // Keyboard ENTER to fix vector offset, ESC to erase drag line
    window.addEventListener('keydown', (e) => {
      if (this.isCalibrating) {
        if (e.key === 'Enter') this.applyCalibrationOffset();
        else if (e.key === 'Escape') this.calibTargetPoint = null;
      }
    });

    // Mouse / Touch Impact & Calibration Drag Listeners
    this.canvas.addEventListener('mousedown', (e) => {
      if (e.ctrlKey) {
        // CTRL+Click simulates direct THUD impact at mouse point
        const margin = this.getMargin();
        const targetWidth = this.canvas.width - (2 * margin);
        const targetHeight = this.canvas.height - (2 * margin);
        const u = (e.clientX - margin) / targetWidth;
        const v = (e.clientY - margin) / targetHeight;
        this.addImpact(u, v);
        return;
      }

      if (this.isCalibrating) {
        if (!this.lastThudPoint) {
          // If no thud point exists yet, click places simulated thud hit
          const margin = this.getMargin();
          const targetWidth = this.canvas.width - (2 * margin);
          const targetHeight = this.canvas.height - (2 * margin);
          const u = (e.clientX - margin) / targetWidth;
          const v = (e.clientY - margin) / targetHeight;
          this.addImpact(u, v);
        } else {
          // Start drag line from existing lastThudPoint to target mouse position
          this.isDraggingCalib = true;
          this.calibTargetPoint = { x: e.clientX, y: e.clientY };
        }
      } else {
        // Direct click fallback test
        const margin = this.getMargin();
        const targetWidth = this.canvas.width - (2 * margin);
        const targetHeight = this.canvas.height - (2 * margin);
        const u = (e.clientX - margin) / targetWidth;
        const v = (e.clientY - margin) / targetHeight;
        this.addImpact(u, v);
      }
    });

    this.canvas.addEventListener('mousemove', (e) => {
      if (this.isCalibrating && this.isDraggingCalib) {
        this.calibTargetPoint = { x: e.clientX, y: e.clientY };
      }
    });

    window.addEventListener('mouseup', () => {
      if (this.isCalibrating) this.isDraggingCalib = false;
    });

    // Game Launcher Menu Links
    document.querySelectorAll('[data-game-id]').forEach(item => {
      item.addEventListener('click', (e) => {
        const gameId = e.currentTarget.getAttribute('data-game-id');
        this.switchGame(gameId);
        // Close Drawer menu if open
        const drawer = document.getElementById('drawer');
        const overlay = document.getElementById('drawerOverlay');
        if (drawer) drawer.classList.remove('open');
        if (overlay) overlay.classList.remove('open');
      });
    });
  }

  /**
   * Hot-swaps the active game module, re-initializing state and mounting custom UI options.
   */
  switchGame(gameId) {
    if (!this.games[gameId]) return;
    this.activeGame = this.games[gameId];
    this.currentGameTitle.innerText = this.activeGame.name;
    this.victoryBadge.style.display = 'none';

    // Pause bug speed during calibration if needed
    if (this.isCalibrating && this.activeGame.id === 'bug_squash' && this.activeGame.bug) {
      this.activeGame.bug.speed = 0;
    }

    this.activeGame.init(this.canvas, this.getMargin());
    this.renderGameOptions();
    this.updateHudStats();
  }

  /**
   * Toggles vector spatial calibration mode.
   */
  toggleCalibrationMode() {
    if (!this.isCalibrating) {
      this.isCalibrating = true;
      this.calibTargetPoint = null;
      this.lastThudPoint = null;
      this.calibBtn.classList.add('active');
      this.calibBtn.innerText = '📌 CALIB ON';
      this.calibBanner.innerHTML = '📌 <b>CALIBRATION MODE</b>: Hit wall with ball (or click canvas/CTRL+Click). Drag line from THUD to target point. Press <b>ENTER</b> to fix offset, <b>ESC</b> to erase line. Click <b>📌 CALIB ON</b> to exit.';
      this.calibBanner.style.display = 'block';
      this.canvas.style.cursor = 'crosshair';

      if (this.activeGame && this.activeGame.id === 'bug_squash' && this.activeGame.bug) {
        this.activeGame.bug.speed = 0;
      }
    } else {
      this.cancelCalibration();
    }
  }

  cancelCalibration() {
    this.isCalibrating = false;
    this.calibTargetPoint = null;
    this.lastThudPoint = null;
    this.calibBtn.classList.remove('active');
    this.calibBtn.innerText = '📌 Calib';
    this.calibBanner.style.display = 'none';
    this.canvas.style.cursor = 'default';

    if (this.activeGame && this.activeGame.id === 'bug_squash' && this.activeGame.bug) {
      const savedSpeed = localStorage.getItem('thud_bug_speed');
      this.activeGame.bug.speed = savedSpeed !== null ? parseFloat(savedSpeed) : 2.0;
    }
  }

  /**
   * Applies the calculated vector offset (ΔX, ΔY) from lastThudPoint to calibTargetPoint.
   */
  applyCalibrationOffset() {
    if (this.isCalibrating && this.lastThudPoint && this.calibTargetPoint) {
      const dx = Math.round(this.calibTargetPoint.x - this.lastThudPoint.x);
      const dy = Math.round(this.calibTargetPoint.y - this.lastThudPoint.y);

      let curOffX = this.getOffsetX();
      let curOffY = this.getOffsetY();

      const newOffX = Math.max(-200, Math.min(200, curOffX + dx));
      const newOffY = Math.max(-200, Math.min(200, curOffY + dy));

      this.offsetXInput.value = newOffX;
      this.offsetYInput.value = newOffY;
      this.saveSettings();

      this.calibTargetPoint = null;
      this.lastThudPoint = null;
      this.calibBanner.innerHTML = `📌 <b>OFFSET FIXED! (Off X: ${newOffX}, Off Y: ${newOffY})</b> Hit wall again (or CTRL+Click) to test. Press <b>ESC</b> to erase line. Click <b>📌 CALIB ON</b> to exit.`;
    }
  }

  /**
   * Handles incoming proportional impact coordinates (u: 0..1, v: 0..1), applying offsets and dispatching to active game.
   */
  addImpact(u, v) {
    const margin = this.getMargin();
    const targetWidth = this.canvas.width - (2 * margin);
    const targetHeight = this.canvas.height - (2 * margin);

    const offX = this.getOffsetX();
    const offY = this.getOffsetY();

    const screenX = margin + (u * targetWidth) + offX;
    const screenY = margin + (v * targetHeight) + offY;

    this.lastThudPoint = { x: screenX, y: screenY, u: u, v: v };

    if (this.isCalibrating) {
      this.calibTargetPoint = null;
      this.ripples.push({
        x: screenX, y: screenY, radius: 10, maxRadius: 180, alpha: 1.0, color: '#ff00aa', text: 'THUD IMPACT'
      });
      return;
    }

    // Dispatch impact to active game module
    const res = this.activeGame.onImpact(u, v, screenX, screenY);

    // Spawn ripple & neon contact point feedback
    this.ripples.push({
      x: screenX, y: screenY, radius: 10, maxRadius: 160, alpha: 1.0,
      color: res.hit ? '#16a34a' : '#dc2626',
      text: res.message || (res.hit ? 'HIT!' : 'MISS')
    });

    this.updateHudStats();

    if (res.won) {
      this.victoryText.innerText = res.message || '🏆 YOU WIN!';
      this.victoryBadge.style.display = 'flex';
    }
  }

  updateHudStats() {
    if (this.hudStatsText && this.activeGame && this.activeGame.getStatsText) {
      this.hudStatsText.innerText = this.activeGame.getStatsText();
    }
  }

  /**
   * Establishes real-time WebSocket stream with Cloudflare Workers relay.
   */
  connectWebSocket() {
    let rawUrl = (this.wsUrlInput ? this.wsUrlInput.value : '').trim() || 'mcp.agility-maint.net';
    const room = (this.roomInput ? this.roomInput.value : '').trim() || 'thud-room-1';

    if (!rawUrl.startsWith('ws://') && !rawUrl.startsWith('wss://')) {
      rawUrl = `wss://${rawUrl}`;
    }

    const fullUrl = `${rawUrl.replace(/\/$/, '')}/thud?room=${encodeURIComponent(room)}`;

    if (this.socket) this.socket.close();

    if (this.statusDot) {
      this.statusDot.className = 'dot';
      this.statusDot.title = `Connecting to ${fullUrl}…`;
    }

    try {
      this.socket = new WebSocket(fullUrl);
      this.socket.onopen = () => {
        if (this.statusDot) {
          this.statusDot.className = 'dot connected';
          this.statusDot.title = `ONLINE (${room}) - Connected to ${fullUrl}`;
        }
        this.saveSettings();
        console.log('[Thud Core] WebSocket Connected:', fullUrl);
      };
      this.socket.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          if (data.type === 'hit' || (data.u !== undefined && data.v !== undefined)) {
            this.addImpact(data.u, data.v);
          }
        } catch (e) {
          console.error('[Thud Core] Invalid WS message:', event.data);
        }
      };
      this.socket.onclose = () => {
        if (this.statusDot) {
          this.statusDot.className = 'dot';
          this.statusDot.title = 'DISCONNECTED. Click Connect to link relay.';
        }
      };
      this.socket.onerror = (err) => {
        if (this.statusDot) {
          this.statusDot.className = 'dot';
          this.statusDot.title = 'CONNECTION ERROR';
        }
      };
    } catch (e) {
      console.error('[Thud Core] WebSocket connection exception:', e);
    }
  }

  /**
   * Main 60 FPS Render Loop.
   */
  loop(now) {
    const dt = now - this.lastFrameTime;
    this.lastFrameTime = now;

    // Clear Canvas
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    const margin = this.getMargin();

    // Render Calibration Border Box in high contrast for light mode
    this.ctx.strokeStyle = 'rgba(15, 23, 42, 0.2)';
    this.ctx.lineWidth = 1.5;
    this.ctx.setLineDash([6, 6]);
    this.ctx.strokeRect(margin, margin, this.canvas.width - (2 * margin), this.canvas.height - (2 * margin));
    this.ctx.setLineDash([]);

    // Update and Draw Active Game Module
    if (this.activeGame) {
      this.activeGame.update(dt, margin);
      this.activeGame.draw(this.ctx);
    }

    // Render Impact Ripples + Small Solid Neon Contact Point Circle
    for (let i = this.ripples.length - 1; i >= 0; i--) {
      const r = this.ripples[i];
      r.radius += 4.5;
      r.alpha -= 0.025;

      if (r.alpha <= 0 || r.radius >= r.maxRadius) {
        this.ripples.splice(i, 1);
        continue;
      }

      this.ctx.save();
      this.ctx.globalAlpha = Math.max(0, r.alpha);

      // 1. Outer expanding shockwave ring
      this.ctx.beginPath();
      this.ctx.arc(r.x, r.y, r.radius, 0, Math.PI * 2);
      this.ctx.strokeStyle = r.color;
      this.ctx.lineWidth = 4;
      this.ctx.shadowColor = r.color;
      this.ctx.shadowBlur = 16;
      this.ctx.stroke();

      // 2. Small solid neon contact point circle pointing to exact contact location
      this.ctx.beginPath();
      this.ctx.arc(r.x, r.y, 8, 0, Math.PI * 2);
      this.ctx.fillStyle = r.color;
      this.ctx.shadowColor = r.color;
      this.ctx.shadowBlur = 12;
      this.ctx.fill();

      // 3. Impact text label next to point of contact
      this.ctx.fillStyle = r.color;
      this.ctx.font = 'bold 15px system-ui';
      this.ctx.fillText(r.text, r.x + 16, r.y - 16);
      this.ctx.restore();
    }

    // Render Calibration Drag Line
    if (this.isCalibrating && this.lastThudPoint) {
      this.ctx.save();
      this.ctx.beginPath();
      this.ctx.arc(this.lastThudPoint.x, this.lastThudPoint.y, 10, 0, Math.PI * 2);
      this.ctx.strokeStyle = '#d946ef';
      this.ctx.lineWidth = 3;
      this.ctx.stroke();
      this.ctx.fillStyle = '#d946ef';
      this.ctx.font = 'bold 12px monospace';
      this.ctx.fillText('THUD IMPACT', this.lastThudPoint.x + 14, this.lastThudPoint.y - 12);

      if (this.calibTargetPoint) {
        this.ctx.beginPath();
        this.ctx.setLineDash([6, 6]);
        this.ctx.moveTo(this.lastThudPoint.x, this.lastThudPoint.y);
        this.ctx.lineTo(this.calibTargetPoint.x, this.calibTargetPoint.y);
        this.ctx.strokeStyle = '#d97706';
        this.ctx.lineWidth = 3;
        this.ctx.stroke();
        this.ctx.setLineDash([]);

        this.ctx.beginPath();
        this.ctx.arc(this.calibTargetPoint.x, this.calibTargetPoint.y, 8, 0, Math.PI * 2);
        this.ctx.fillStyle = '#d97706';
        this.ctx.fill();

        const dx = Math.round(this.calibTargetPoint.x - this.lastThudPoint.x);
        const dy = Math.round(this.calibTargetPoint.y - this.lastThudPoint.y);
        const midX = (this.lastThudPoint.x + this.calibTargetPoint.x) / 2;
        const midY = (this.lastThudPoint.y + this.calibTargetPoint.y) / 2;
        this.ctx.fillStyle = '#d97706';
        this.ctx.font = 'bold 13px monospace';
        this.ctx.fillText(`ΔX: ${dx >= 0 ? '+' : ''}${dx}px | ΔY: ${dy >= 0 ? '+' : ''}${dy}px`, midX + 10, midY - 10);
      }
      this.ctx.restore();
    }

    requestAnimationFrame((t) => this.loop(t));
  }
}
