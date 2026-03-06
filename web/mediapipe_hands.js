// ────────────────────────────────────────────────────────────
// SAHA — MediaPipe Hands Bridge
// Real-time 21-landmark hand tracking via webcam
// ────────────────────────────────────────────────────────────

let _mpHands = null;
let _mpCamera = null;
let _mpVideo = null;
let _mpCanvas = null;
let _mpCtx = null;
let _mpActive = false;
let _mpLandmarks = null;   // flat array: [x0,y0,z0, x1,y1,z1, ...]
let _mpHandedness = '';     // 'Left' or 'Right'

// ─── Initialise DOM elements + MediaPipe (called once) ─────

function _mpInit() {
  // Hidden video for camera feed
  _mpVideo = document.createElement('video');
  _mpVideo.id = 'saha-mp-video';
  _mpVideo.autoplay = true;
  _mpVideo.playsInline = true;
  _mpVideo.style.display = 'none';
  document.body.appendChild(_mpVideo);

  // Visible canvas — camera preview with skeleton overlay
  _mpCanvas = document.createElement('canvas');
  _mpCanvas.id = 'saha-mp-canvas';
  _mpCanvas.width = 320;
  _mpCanvas.height = 240;
  Object.assign(_mpCanvas.style, {
    position: 'fixed',
    bottom: '180px',
    left: '16px',
    zIndex: '100000',
    borderRadius: '14px',
    border: '3px solid #4CAF50',
    boxShadow: '0 6px 24px rgba(0,0,0,0.6)',
    display: 'none',
    transform: 'scaleX(-1)',           // mirror (selfie view)
    background: '#000',
  });
  document.body.appendChild(_mpCanvas);
  _mpCtx = _mpCanvas.getContext('2d');

  // Gesture label overlay
  var label = document.createElement('div');
  label.id = 'saha-mp-label';
  Object.assign(label.style, {
    position: 'fixed',
    bottom: '425px',
    left: '16px',
    zIndex: '100001',
    color: '#fff',
    background: 'rgba(0,0,0,0.7)',
    padding: '4px 14px',
    borderRadius: '8px',
    fontSize: '13px',
    fontWeight: 'bold',
    fontFamily: 'system-ui, sans-serif',
    display: 'none',
    minWidth: '120px',
    textAlign: 'center',
  });
  document.body.appendChild(label);

  // MediaPipe Hands
  _mpHands = new Hands({
    locateFile: function(file) {
      return 'https://cdn.jsdelivr.net/npm/@mediapipe/hands/' + file;
    },
  });
  _mpHands.setOptions({
    maxNumHands: 1,
    modelComplexity: 1,
    minDetectionConfidence: 0.65,
    minTrackingConfidence: 0.5,
  });
  _mpHands.onResults(_mpOnResults);
}

// ─── Process each frame from MediaPipe ─────────────────────

function _mpOnResults(results) {
  if (!_mpCtx || !_mpCanvas) return;
  _mpCtx.save();
  _mpCtx.clearRect(0, 0, _mpCanvas.width, _mpCanvas.height);
  _mpCtx.drawImage(results.image, 0, 0, _mpCanvas.width, _mpCanvas.height);

  if (results.multiHandLandmarks && results.multiHandLandmarks.length > 0) {
    var lm = results.multiHandLandmarks[0];

    // Draw skeleton
    drawConnectors(_mpCtx, lm, HAND_CONNECTIONS, {
      color: '#00FF00', lineWidth: 2,
    });
    drawLandmarks(_mpCtx, lm, {
      color: '#FF0044', lineWidth: 1, radius: 4,
    });

    // Flatten to [x0,y0,z0, ...] (63 values)
    var flat = new Array(63);
    for (var i = 0; i < 21; i++) {
      flat[i * 3]     = lm[i].x;
      flat[i * 3 + 1] = lm[i].y;
      flat[i * 3 + 2] = lm[i].z;
    }
    _mpLandmarks = flat;

    // Handedness
    if (results.multiHandedness && results.multiHandedness.length > 0) {
      _mpHandedness = results.multiHandedness[0].label;
    }

    // Update label
    var el = document.getElementById('saha-mp-label');
    if (el) {
      el.textContent = '\u270B Hand detected (' + _mpHandedness + ')';
      el.style.display = 'block';
    }
  } else {
    _mpLandmarks = null;
    _mpHandedness = '';
    var el = document.getElementById('saha-mp-label');
    if (el) el.textContent = '\uD83D\uDC4B Show your hand';
  }
  _mpCtx.restore();
}

// ─── Public API (called from Dart via JS interop) ──────────

function startHandTracking() {
  if (_mpActive) return;
  if (!_mpHands) _mpInit();

  _mpCanvas.style.display = 'block';
  var el = document.getElementById('saha-mp-label');
  if (el) el.style.display = 'block';

  _mpCamera = new Camera(_mpVideo, {
    onFrame: async function() { await _mpHands.send({ image: _mpVideo }); },
    width: 320,
    height: 240,
  });
  _mpCamera.start();
  _mpActive = true;
  console.log('[SAHA] MediaPipe Hands started');
}

function stopHandTracking() {
  if (!_mpActive) return;
  if (_mpCamera) { _mpCamera.stop(); _mpCamera = null; }
  _mpActive = false;
  _mpLandmarks = null;
  if (_mpCanvas) _mpCanvas.style.display = 'none';
  var el = document.getElementById('saha-mp-label');
  if (el) el.style.display = 'none';
  console.log('[SAHA] MediaPipe Hands stopped');
}

function getHandLandmarksJson() {
  if (!_mpLandmarks) return '';
  return _mpLandmarks.join(',');
}

function getHandedness() {
  return _mpHandedness || '';
}

function isMediaPipeAvailable() {
  return typeof Hands !== 'undefined' && typeof Camera !== 'undefined';
}

function isHandTrackingActive() {
  return _mpActive === true;
}
