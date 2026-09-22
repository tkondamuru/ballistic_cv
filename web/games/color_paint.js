// Modular Game: Neon Paint Splatters
export default class ColorPaintGame {
  constructor() {
    this.name = "🎨 Neon Paint Splatters";
    this.id = "color_paint";
    this.totalSplatters = 0;
    this.paintSplatters = [];
    this.paintDrips = [];
    this.splatterRadius = 25;

    this.NEON_PALETTE = ['#ff0055', '#00e5ff', '#ffd700', '#ff00aa', '#00ff66', '#a78bfa', '#ff5722'];
  }

  init(canvas, margin) {
    this.canvas = canvas;
    this.margin = margin || 24;
    this.totalSplatters = 0;
    this.paintSplatters = [];
    this.paintDrips = [];

    const savedRadius = localStorage.getItem('thud_paint_radius');
    if (savedRadius !== null) this.splatterRadius = parseInt(savedRadius) || 25;
  }

  renderOptions(container) {
    container.innerHTML = `
      <div class="input-group" title="Paint Splatter Size">
        <label>Splat Size:</label>
        <input type="range" id="splatSizeSlider" min="15" max="50" value="${this.splatterRadius}" style="width: 45px;">
        <span id="splatSizeVal" class="val-readout">${this.splatterRadius}px</span>
      </div>
      <button id="clearCanvasBtn" class="btn" style="background:#475569; padding: 3px 8px; font-size: 11px;">Clear</button>
    `;

    const splatSlider = container.querySelector('#splatSizeSlider');
    const splatVal = container.querySelector('#splatSizeVal');
    const clearBtn = container.querySelector('#clearCanvasBtn');

    splatSlider.addEventListener('input', (e) => {
      this.splatterRadius = parseInt(e.target.value);
      splatVal.innerText = `${this.splatterRadius}px`;
      localStorage.setItem('thud_paint_radius', this.splatterRadius);
    });

    clearBtn.addEventListener('click', () => {
      this.paintSplatters = [];
      this.paintDrips = [];
      this.totalSplatters = 0;
    });
  }

  update(dt, margin) {
    this.margin = margin || 24;
  }

  createPaintSplatter(x, y) {
    const color = this.NEON_PALETTE[Math.floor(Math.random() * this.NEON_PALETTE.length)];
    const baseRadius = this.splatterRadius + Math.random() * 10;
    const droplets = [];
    const numDroplets = 18 + Math.floor(Math.random() * 25);

    for (let i = 0; i < numDroplets; i++) {
      const angle = Math.random() * Math.PI * 2;
      const dist = baseRadius + Math.random() * 55;
      droplets.push({
        x: x + Math.cos(angle) * dist,
        y: y + Math.sin(angle) * dist,
        r: 2 + Math.random() * 7
      });
    }

    if (Math.random() < 0.6) {
      this.paintDrips.push({
        x: x + (Math.random() * 20 - 10),
        y: y + baseRadius,
        length: 0,
        maxLength: 40 + Math.random() * 100,
        speed: 1.5 + Math.random() * 2,
        color: color,
        width: 3 + Math.random() * 4
      });
    }

    this.paintSplatters.push({
      x: x, y: y,
      baseRadius: baseRadius,
      droplets: droplets,
      color: color
    });

    this.totalSplatters++;
  }

  onImpact(u, v, screenX, screenY) {
    this.createPaintSplatter(screenX, screenY);
    return {
      hit: true,
      won: false,
      message: 'SPLASH!'
    };
  }

  draw(ctx) {
    for (const s of this.paintSplatters) {
      ctx.save();
      ctx.fillStyle = s.color;
      ctx.shadowColor = s.color;
      ctx.shadowBlur = 12;

      ctx.beginPath();
      ctx.arc(s.x, s.y, s.baseRadius, 0, Math.PI * 2);
      ctx.fill();

      for (const d of s.droplets) {
        ctx.beginPath();
        ctx.arc(d.x, d.y, d.r, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();
    }

    for (const d of this.paintDrips) {
      if (d.length < d.maxLength) d.length += d.speed;

      ctx.save();
      ctx.strokeStyle = d.color;
      ctx.lineWidth = d.width;
      ctx.lineCap = 'round';
      ctx.shadowColor = d.color;
      ctx.shadowBlur = 8;

      ctx.beginPath();
      ctx.moveTo(d.x, d.y);
      ctx.lineTo(d.x, d.y + d.length);
      ctx.stroke();

      ctx.beginPath();
      ctx.arc(d.x, d.y + d.length, d.width * 0.8, 0, Math.PI * 2);
      ctx.fillStyle = d.color;
      ctx.fill();
      ctx.restore();
    }
  }

  getStatsText() {
    return `🎨 SPLATTERS: ${this.totalSplatters}`;
  }
}
