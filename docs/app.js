(() => {
  const PRESETS = {
    fast: {
      phase: 'Fast Charge',
      symbol: '⚡',
      accent: '#28cd6e',
      accentBg: 'rgba(40, 205, 110, 0.18)',
      accentBorder: 'rgba(40, 205, 110, 0.34)',
      watts: 94.2,
      volts: 20.0,
      amps: 4.71,
      pct: 78,
      sysWatts: 24.8,
      batWatts: 69.4,
      batSigned: '+69.4W',
      inLabel: 'In 94.2W',
      pdBadge: '140W PD',
      eta: '28m to full',
      temp: '31.4°C',
      thermal: 'Nominal',
      adapterTitle: 'Apple 140W USB-C Power Adapter',
      protocol: 'USB-PD EPR',
      contract: '20.0 V · 5.00 A (140W)',
      cells: '4.23V · 4.23V · 4.22V (Δ 3 mV)',
      curve: [42, 56, 68, 79, 88, 95, 96, 94, 92, 95, 94, 93, 95, 94.2]
    },
    desk: {
      phase: 'Charging',
      symbol: '⚡',
      accent: '#28cd6e',
      accentBg: 'rgba(40, 205, 110, 0.18)',
      accentBorder: 'rgba(40, 205, 110, 0.34)',
      watts: 58.4,
      volts: 20.0,
      amps: 2.92,
      pct: 52,
      sysWatts: 19.2,
      batWatts: 39.2,
      batSigned: '+39.2W',
      inLabel: 'In 58.4W',
      pdBadge: '67W PD',
      eta: '44m to full',
      temp: '30.2°C',
      thermal: 'Nominal',
      adapterTitle: '67W USB-C Studio Display PD',
      protocol: 'USB-PD 3.0',
      contract: '20.0 V · 3.35 A (67W)',
      cells: '3.98V · 3.98V · 3.97V (Δ 4 mV)',
      curve: [38, 46, 54, 57, 59, 60, 58, 57, 59, 60, 58.5, 57.9, 58.2, 58.4]
    },
    hold: {
      phase: 'Optimized',
      symbol: '✦',
      accent: '#f59e0b',
      accentBg: 'rgba(245, 158, 11, 0.18)',
      accentBorder: 'rgba(245, 158, 11, 0.38)',
      watts: 16.8,
      volts: 20.0,
      amps: 0.84,
      pct: 80,
      sysWatts: 16.8,
      batWatts: 0.0,
      batSigned: '0.0W',
      inLabel: 'In 16.8W',
      pdBadge: 'AC Hold',
      eta: 'Holding at 80%',
      temp: '28.6°C',
      thermal: 'Nominal',
      adapterTitle: 'Apple 140W USB-C Power Adapter',
      protocol: 'USB-PD Passthrough',
      contract: '20.0 V · 5.00 A (140W)',
      cells: '4.12V · 4.12V · 4.12V (Δ 1 mV)',
      curve: [62, 55, 44, 32, 22, 18, 17, 16.5, 17.2, 16.4, 16.9, 16.6, 17.0, 16.8]
    },
    battery: {
      phase: 'On Battery',
      symbol: '◔',
      accent: '#3fa9ff',
      accentBg: 'rgba(63, 169, 255, 0.18)',
      accentBorder: 'rgba(63, 169, 255, 0.36)',
      watts: 14.6,
      volts: 11.84,
      amps: 1.23,
      pct: 64,
      sysWatts: 14.6,
      batWatts: 0.0,
      batSigned: '−14.6W',
      inLabel: 'Unplugged',
      pdBadge: 'Battery',
      eta: '5h 12m left',
      temp: '29.1°C',
      thermal: 'Nominal',
      adapterTitle: 'Internal Apple Silicon Battery Pack',
      protocol: 'Discharging',
      contract: '3-Cell Li-Ion · 6075 mAh Design',
      cells: '3.95V · 3.95V · 3.94V (Δ 2 mV)',
      curve: [18, 22, 19, 15, 13, 16, 17, 14, 13.5, 15.2, 16.0, 14.9, 14.2, 14.6]
    }
  };

  const el = (id) => document.getElementById(id);

  function buildSparkline(values, width = 180, height = 68) {
    const padTop = 8;
    const padBot = 6;
    const usableH = height - padTop - padBot;
    const maxVal = Math.max(...values, 20);
    const minVal = Math.max(0, Math.min(...values) * 0.72);
    const span = Math.max(maxVal - minVal, 6);

    const pts = values.map((v, idx) => {
      const x = (idx / (values.length - 1)) * (width - 6) + 2;
      const norm = (v - minVal) / span;
      const y = padTop + usableH * (1 - norm);
      return [x, y];
    });

    let line = `M ${pts[0][0].toFixed(1)} ${pts[0][1].toFixed(1)}`;
    for (let i = 1; i < pts.length; i++) {
      const prev = pts[i - 1];
      const curr = pts[i];
      const mx = (prev[0] + curr[0]) / 2;
      const my = (prev[1] + curr[1]) / 2;
      if (i === 1) {
        line += ` L ${mx.toFixed(1)} ${my.toFixed(1)}`;
      } else {
        line += ` Q ${prev[0].toFixed(1)} ${prev[1].toFixed(1)} ${mx.toFixed(1)} ${my.toFixed(1)}`;
      }
      if (i === pts.length - 1) {
        line += ` L ${curr[0].toFixed(1)} ${curr[1].toFixed(1)}`;
      }
    }

    const last = pts[pts.length - 1];
    const first = pts[0];
    const area = `${line} L ${last[0].toFixed(1)} ${height} L ${first[0].toFixed(1)} ${height} Z`;
    return { line, area, last };
  }

  function applyPreset(key) {
    const p = PRESETS[key] || PRESETS.fast;

    // Menu bar status item
    el('sim-menubar-label').textContent = `${p.symbol} ${p.watts.toFixed(1)}W`;

    // Medium widget
    const medPhase = el('w-med-phase');
    medPhase.textContent = `${p.symbol} ${p.phase}`;
    medPhase.style.color = p.accent;
    el('w-med-watts').textContent = p.watts.toFixed(1);
    el('w-med-va').textContent = `${p.volts.toFixed(1)}V · ${p.amps.toFixed(2)}A · ${p.pct}%`;
    el('w-med-pd').textContent = p.pdBadge;
    el('w-med-eta').textContent = `${p.eta} · 98%`;

    // Power Flow bars
    const total = p.sysWatts + Math.max(p.batWatts, 0);
    const sysPct = total > 0 ? Math.max(10, Math.min(100, (p.sysWatts / total) * 100)) : 100;
    const batPct = Math.max(0, 100 - sysPct);

    el('w-med-sysbar').style.width = `${sysPct}%`;
    el('w-med-batbar').style.width = `${batPct}%`;
    el('p-sysbar').style.width = `${sysPct}%`;
    el('p-batbar').style.width = `${batPct}%`;

    const sysPrefix = key === 'battery' ? 'Draw' : 'System';
    el('w-med-sys').textContent = `${sysPrefix} ${p.sysWatts.toFixed(1)}W`;
    el('w-med-bat').textContent = `Battery ${p.batSigned}`;
    el('p-sys').textContent = `${sysPrefix} ${p.sysWatts.toFixed(1)}W`;
    el('p-bat').textContent = `Battery ${p.batSigned}`;

    // Sparkline SVG
    const spark = buildSparkline(p.curve);
    el('spark-line').setAttribute('d', spark.line);
    el('spark-line').setAttribute('stroke', p.accent);
    el('spark-area').setAttribute('d', spark.area);
    el('spark-stop-top').setAttribute('stop-color', p.accent);
    el('spark-stop-bot').setAttribute('stop-color', p.accent);
    const dot = el('spark-dot');
    dot.setAttribute('cx', spark.last[0].toFixed(1));
    dot.setAttribute('cy', spark.last[1].toFixed(1));
    dot.setAttribute('fill', p.accent);

    // Small widget ring
    const circumference = 2 * Math.PI * 58;
    const offset = circumference * (1 - p.pct / 100);
    const ring = el('w-small-ring');
    ring.style.strokeDashoffset = offset.toFixed(1);
    ring.style.stroke = p.accent;
    el('w-small-watts').textContent = `${p.watts.toFixed(1)}W`;
    el('w-small-pct').textContent = `${p.pct}%`;
    el('w-small-va').textContent = `${p.volts.toFixed(1)}V · ${p.amps.toFixed(1)}A`;

    // Adapter card
    el('w-adapter-title').textContent = p.adapterTitle;
    el('w-adapter-proto').textContent = p.protocol;
    el('w-adapter-contract').textContent = p.contract;
    el('w-adapter-cells').textContent = p.cells;
    el('w-adapter-thermal').textContent = p.thermal;

    // Popover
    el('p-eta').textContent = p.eta;
    const chip = el('p-phase');
    chip.textContent = p.phase;
    chip.style.color = p.accent;
    chip.style.background = p.accentBg;
    chip.style.borderColor = p.accentBorder;

    el('p-watts').textContent = p.watts.toFixed(1);
    el('p-volts').textContent = `${p.volts.toFixed(2)} V`;
    el('p-amps').textContent = `${p.amps.toFixed(2)} A`;
    el('p-pct').textContent = `${p.pct}%`;
    el('p-in').textContent = p.inLabel;
    el('p-temp').textContent = p.temp;
    el('p-thermal').textContent = p.thermal;
  }

  // Preset tab bindings
  const tabs = document.querySelectorAll('.sim-tab');
  tabs.forEach((tab) => {
    tab.addEventListener('click', () => {
      tabs.forEach((t) => {
        t.classList.remove('is-active');
        t.setAttribute('aria-selected', 'false');
      });
      tab.classList.add('is-active');
      tab.setAttribute('aria-selected', 'true');
      applyPreset(tab.dataset.preset);
    });
  });

  // Copy install command
  const copyBtn = el('copy-install');
  const installCmd = el('install-cmd');
  if (copyBtn && installCmd) {
    copyBtn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(installCmd.textContent.trim());
        copyBtn.textContent = 'Copied';
        setTimeout(() => {
          copyBtn.textContent = 'Copy';
        }, 1800);
      } catch {
        copyBtn.textContent = 'Select & Copy';
      }
    });
  }

  // Initialize default scenario
  applyPreset('fast');
})();
