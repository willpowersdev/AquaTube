/* 
 *  Chromatic AquaTube v. 1.0.0
 *  Written by Will Powers
 */
#include <ArduinoBLE.h>

uint8_t initialColor[3] = { 0, 255, 255 };

BLEService deviceService("19B10010-E8F2-537E-4F6C-D104768A1214");

// Define the characteristic UUIDs
BLECharacteristic colorWheelCharacteristic("19B10011-E8F2-537E-4F6C-D104768A1214", BLEWrite, 3, false);
BLECharacteristic colorCommandCharacteristic("19B10012-E8F2-537E-4F6C-D104768A1214", BLEWrite, 1, false);

int redPin = D3;    // Red LED 
int greenPin = D5;    // Green LED
int bluePin = D6;    // Blue LED

// Commands written to colorCommandCharacteristic
const uint8_t COMMAND_OFF = 0;
const uint8_t COMMAND_FIRELIGHT = 1;
const uint8_t COMMAND_STORMS = 2;
const uint8_t COMMAND_CHRISTMAS = 3;
const uint8_t COMMAND_FOURTH_OF_JULY = 4;
const uint8_t COMMAND_DEFAULT_COLOR = 5;

// Firelight routine state. Adapted from the Fire animation in
// https://github.com/Electriangle/Fire_Main (MIT License,
// Copyright (c) 2022 Electriangle). That effect simulates heat rising
// through a strip of LEDs; the AquaTube has a single RGB LED, so the same
// simulation runs on a virtual column and the LED shows the column's
// blended color, as the tube would diffuse it.
const int FIRE_CELLS = 50;           // virtual strip length (Fire_Main default)
const int FIRE_FLAME_HEIGHT = 50;    // larger = shorter flames (Fire_Main default)
const int FIRE_SPARKS = 100;         // 0-255, larger = more active fire (Fire_Main default)
const unsigned long FIRE_FRAME_MS = 10;  // Fire_Main's DelayDuration, without blocking
bool firelightActive = false;
uint8_t fireHeat[FIRE_CELLS];
unsigned long fireLastFrameAt = 0;

// Christmas routine state. Holds on each color, crossfades to the next,
// and scatters brief gold sparkles on top.
// Keep colors and timings in sync with ChristmasPreview in the iOS app.
const uint8_t CHRISTMAS_COLORS[][3] = {
  { 255, 0, 0 },     // red
  { 255, 140, 0 },   // gold
  { 0, 255, 20 },    // green
  { 255, 140, 0 },   // gold
};
const int CHRISTMAS_COLOR_COUNT = sizeof(CHRISTMAS_COLORS) / sizeof(CHRISTMAS_COLORS[0]);
const uint8_t CHRISTMAS_SPARKLE[3] = { 255, 200, 80 };
const unsigned long CHRISTMAS_HOLD_MS = 2500;
const unsigned long CHRISTMAS_FADE_MS = 1500;
const unsigned long CHRISTMAS_FRAME_MS = 15;
bool christmasActive = false;
int christmasIndex = 0;
unsigned long christmasSegmentStart = 0;
float christmasSparkle = 0.0;     // 0 = base color, 1 = full sparkle
unsigned long christmasNextSparkleAt = 0;
unsigned long christmasLastFrameAt = 0;

// 4th of July routine state. Crossfades through red, white and blue, fades
// to a night sky, puts on a fireworks show that ends in a finale, and repeats.
// Keep colors and timings in sync with FourthOfJulyPreview in the iOS app.
struct Keyframe {
  uint8_t color[3];
  unsigned long holdMs;
  unsigned long fadeMs;   // crossfade to the next keyframe
};
const Keyframe JULY_KEYFRAMES[] = {
  { { 2, 2, 8 }, 0, 1000 },         // night, fading in
  { { 255, 0, 0 }, 2000, 1000 },    // red
  { { 255, 255, 255 }, 2000, 1000 },// white
  { { 0, 40, 255 }, 2000, 1000 },   // blue
  { { 2, 2, 8 }, 0, 0 },            // night, then fireworks
};
const int JULY_KEYFRAME_COUNT = sizeof(JULY_KEYFRAMES) / sizeof(JULY_KEYFRAMES[0]);
const uint8_t NIGHT_SKY[3] = { 2, 2, 8 };
const uint8_t LAUNCH_GLOW[3] = { 255, 120, 30 };
const uint8_t FIREWORK_COLORS[][3] = {
  { 255, 0, 0 },       // red
  { 255, 255, 255 },   // white
  { 0, 40, 255 },      // blue
};
const unsigned long FIREWORKS_SHOW_MS = 12000;
const unsigned long FIREWORKS_FINALE_MS = 3500;   // last part of the show
const unsigned long JULY_FRAME_MS = 15;

enum JulyStage { JULY_COLORS, JULY_LAUNCH, JULY_BURST, JULY_GAP };
bool julyActive = false;
JulyStage julyStage = JULY_COLORS;
int julyKeyframe = 0;
unsigned long julyStageStart = 0;
unsigned long julyStageLength = 0;
unsigned long julyShowStart = 0;
float julyBurstLevel = 0.0;
uint8_t julyBurstColor[3] = { 255, 255, 255 };
unsigned long julyLastFrameAt = 0;

// Storms routine state. Rests on dim moonlight, then at random intervals
// fires a strike of one to four quick blue/white flashes that decay back.
bool stormsActive = false;
float moonBrightness = 1.0;       // slow shimmer on the moonlight, 0.8..1
float moonTargetBrightness = 1.0;
float stormFlashLevel = 0.0;      // 0 = moonlight, 1 = full flash color
float stormDecay = 0.85;          // per-frame multiplier once a flash lets go
uint8_t stormFlashColor[3] = { 255, 255, 255 };
uint8_t stormFlashesRemaining = 0;
bool stormHolding = false;
unsigned long stormHoldUntil = 0;
unsigned long stormNextEventAt = 0;
unsigned long stormLastFrameAt = 0;
const unsigned long STORM_FRAME_MS = 10;

// Keep in sync with StormsPreview in the iOS app
const uint8_t MOONLIGHT[3] = { 22, 26, 40 };
const uint8_t LIGHTNING_WHITE[3] = { 255, 255, 255 };
const uint8_t LIGHTNING_BLUE_WHITE[3] = { 170, 200, 255 };
const uint8_t LIGHTNING_BLUE[3] = { 30, 80, 255 };

// Event listeners
void onColorWheelWrite(BLEDevice central, BLECharacteristic characteristic) {
  // Handle the event when characteristic is written
  uint8_t* combinedValue = (uint8_t*)characteristic.value();
  // Picking a solid color stops any running routine
  stopRoutines();
  setColor(combinedValue);
}

void onColorCommandWrite(BLEDevice central, BLECharacteristic characteristic) {
  // Handle the event when characteristic is written
  uint8_t* value = (uint8_t*)characteristic.value();

  switch (value[0]) {
    case COMMAND_OFF:
      stopRoutines();
      setColor(0, 0, 0);
    break;
    case COMMAND_FIRELIGHT:
      startFirelight();
    break;
    case COMMAND_STORMS:
      startStorms();
    break;
    case COMMAND_CHRISTMAS:
      startChristmas();
    break;
    case COMMAND_FOURTH_OF_JULY:
      startFourthOfJuly();
    break;
    case COMMAND_DEFAULT_COLOR:
      stopRoutines();
      setColor(0, 128, 255);
    break;
  }
}

void stopRoutines() {
  firelightActive = false;
  stormsActive = false;
  christmasActive = false;
  julyActive = false;
}

void setColor(uint8_t red, uint8_t green, uint8_t blue) {
  analogWrite(redPin, red);
  analogWrite(greenPin, green);
  analogWrite(bluePin, blue);
}

void setColor(uint8_t rgb[]) {
  analogWrite(redPin, rgb[0]);
  analogWrite(greenPin, rgb[1]);
  analogWrite(bluePin, rgb[2]);
}

// Fire_Main's setPixelHeatColor(): black -> red -> orange/yellow -> white
void heatColor(uint8_t temperature, uint8_t rgb[3]) {
  // Rescale heat from 0-255 to 0-191
  uint8_t t192 = round((temperature / 255.0) * 191);

  // Ramp within the current third of the spectrum, 0..252
  uint8_t heatramp = (t192 & 0x3F) << 2;

  if (t192 > 0x80) {          // hottest
    rgb[0] = 255; rgb[1] = 255; rgb[2] = heatramp;
  } else if (t192 > 0x40) {   // middle
    rgb[0] = 255; rgb[1] = heatramp; rgb[2] = 0;
  } else {                    // coolest
    rgb[0] = heatramp; rgb[1] = 0; rgb[2] = 0;
  }
}

void startFirelight() {
  stopRoutines();
  firelightActive = true;
  memset(fireHeat, 0, sizeof(fireHeat));
  fireLastFrameAt = 0;
}

// One frame of Fire_Main's Fire(). Non-blocking so BLE.poll() keeps running.
void updateFirelight() {
  if (!firelightActive) {
    return;
  }

  unsigned long now = millis();
  if (now - fireLastFrameAt < FIRE_FRAME_MS) {
    return;
  }
  fireLastFrameAt = now;

  // Cool down each cell a little
  for (int i = 0; i < FIRE_CELLS; i++) {
    int cooldown = random(0, ((FIRE_FLAME_HEIGHT * 10) / FIRE_CELLS) + 2);
    fireHeat[i] = cooldown > fireHeat[i] ? 0 : fireHeat[i] - cooldown;
  }

  // Heat from each cell drifts up and diffuses slightly
  for (int k = FIRE_CELLS - 1; k >= 2; k--) {
    fireHeat[k] = (fireHeat[k - 1] + fireHeat[k - 2] + fireHeat[k - 2]) / 3;
  }

  // Randomly ignite new sparks near the bottom of the flame. Saturate
  // instead of letting the byte wrap, which would turn a hot cell cold.
  if (random(255) < FIRE_SPARKS) {
    int y = random(7);
    fireHeat[y] = min(255, fireHeat[y] + (int)random(160, 255));
  }

  // Blend every cell's color into the single LED
  unsigned long total[3] = { 0, 0, 0 };
  uint8_t rgb[3];
  for (int j = 0; j < FIRE_CELLS; j++) {
    heatColor(fireHeat[j], rgb);
    total[0] += rgb[0];
    total[1] += rgb[1];
    total[2] += rgb[2];
  }
  setColor(total[0] / FIRE_CELLS, total[1] / FIRE_CELLS, total[2] / FIRE_CELLS);
}

void fireStormFlash(unsigned long now) {
  if (stormFlashesRemaining == 0) {
    // Start a new strike
    stormFlashesRemaining = random(1, 5);
  }
  stormFlashesRemaining--;

  const uint8_t* color;
  long roll = random(100);
  if (roll < 35) {
    color = LIGHTNING_WHITE;
  } else if (roll < 70) {
    color = LIGHTNING_BLUE_WHITE;
  } else {
    color = LIGHTNING_BLUE;
  }
  memcpy(stormFlashColor, color, 3);

  stormFlashLevel = random(70, 101) / 100.0;
  stormHolding = true;
  stormHoldUntil = now + random(20, 80);
  stormDecay = random(78, 92) / 100.0;

  if (stormFlashesRemaining > 0) {
    // Next flash in the same strike
    stormNextEventAt = now + random(60, 260);
  } else {
    // Quiet moonlight until the next strike
    stormNextEventAt = now + random(2000, 9000);
  }
}

void startStorms() {
  stopRoutines();
  stormsActive = true;
  moonBrightness = 1.0;
  moonTargetBrightness = 1.0;
  stormFlashLevel = 0.0;
  stormFlashesRemaining = 0;
  stormHolding = false;
  stormLastFrameAt = 0;
  stormNextEventAt = millis() + random(1000, 4000);
}

// Non-blocking so BLE.poll() keeps running between frames
void updateStorms() {
  if (!stormsActive) {
    return;
  }

  unsigned long now = millis();
  if (now - stormLastFrameAt < STORM_FRAME_MS) {
    return;
  }
  stormLastFrameAt = now;

  // Moonlight drifts slowly, as if clouds pass in front of it
  if (random(200) == 0) {
    moonTargetBrightness = random(80, 101) / 100.0;
  }
  moonBrightness += (moonTargetBrightness - moonBrightness) * 0.01;

  if (stormHolding) {
    if ((long)(now - stormHoldUntil) >= 0) {
      stormHolding = false;
    }
  } else {
    stormFlashLevel *= stormDecay;
  }

  if (!stormHolding && (long)(now - stormNextEventAt) >= 0) {
    fireStormFlash(now);
  }

  uint8_t rgb[3];
  for (int i = 0; i < 3; i++) {
    float moon = MOONLIGHT[i] * moonBrightness;
    rgb[i] = (uint8_t)(moon + (stormFlashColor[i] - moon) * stormFlashLevel);
  }
  setColor(rgb);
}

void startChristmas() {
  stopRoutines();
  christmasActive = true;
  christmasIndex = 0;
  christmasSegmentStart = millis();
  christmasSparkle = 0.0;
  christmasNextSparkleAt = millis() + random(800, 2500);
  christmasLastFrameAt = 0;
}

// Non-blocking so BLE.poll() keeps running between frames
void updateChristmas() {
  if (!christmasActive) {
    return;
  }

  unsigned long now = millis();
  if (now - christmasLastFrameAt < CHRISTMAS_FRAME_MS) {
    return;
  }
  christmasLastFrameAt = now;

  unsigned long elapsed = now - christmasSegmentStart;
  if (elapsed >= CHRISTMAS_HOLD_MS + CHRISTMAS_FADE_MS) {
    christmasIndex = (christmasIndex + 1) % CHRISTMAS_COLOR_COUNT;
    christmasSegmentStart = now;
    elapsed = 0;
  }

  const uint8_t* from = CHRISTMAS_COLORS[christmasIndex];
  const uint8_t* to = CHRISTMAS_COLORS[(christmasIndex + 1) % CHRISTMAS_COLOR_COUNT];
  float t = 0.0;
  if (elapsed > CHRISTMAS_HOLD_MS) {
    t = (float)(elapsed - CHRISTMAS_HOLD_MS) / CHRISTMAS_FADE_MS;
    t = t * t * (3.0 - 2.0 * t);  // ease in and out
  }

  christmasSparkle *= 0.88;
  if ((long)(now - christmasNextSparkleAt) >= 0) {
    christmasSparkle = random(60, 101) / 100.0;
    christmasNextSparkleAt = now + random(1200, 4000);
  }

  uint8_t rgb[3];
  for (int i = 0; i < 3; i++) {
    float base = from[i] + (to[i] - from[i]) * t;
    rgb[i] = (uint8_t)(base + (CHRISTMAS_SPARKLE[i] - base) * christmasSparkle);
  }
  setColor(rgb);
}

void setJulyStage(JulyStage stage, unsigned long now, unsigned long length) {
  julyStage = stage;
  julyStageStart = now;
  julyStageLength = length;
}

void startFourthOfJuly() {
  stopRoutines();
  julyActive = true;
  julyKeyframe = 0;
  julyBurstLevel = 0.0;
  julyLastFrameAt = 0;
  setJulyStage(JULY_COLORS, millis(), 0);
}

bool inFireworksFinale(unsigned long now) {
  return now - julyShowStart >= FIREWORKS_SHOW_MS - FIREWORKS_FINALE_MS;
}

void launchFirework(unsigned long now) {
  // Rockets go up quicker during the finale
  unsigned long length = inFireworksFinale(now) ? random(120, 250) : random(400, 800);
  setJulyStage(JULY_LAUNCH, now, length);
}

// Non-blocking so BLE.poll() keeps running between frames
void updateFourthOfJuly() {
  if (!julyActive) {
    return;
  }

  unsigned long now = millis();
  if (now - julyLastFrameAt < JULY_FRAME_MS) {
    return;
  }
  julyLastFrameAt = now;

  unsigned long elapsed = now - julyStageStart;
  uint8_t rgb[3];

  switch (julyStage) {
    case JULY_COLORS: {
      const Keyframe& from = JULY_KEYFRAMES[julyKeyframe];
      if (elapsed >= from.holdMs + from.fadeMs) {
        julyKeyframe++;
        julyStageStart = now;
        if (julyKeyframe >= JULY_KEYFRAME_COUNT - 1) {
          // Colors done: start the fireworks show
          julyShowStart = now;
          launchFirework(now);
        }
        return;
      }
      const Keyframe& to = JULY_KEYFRAMES[julyKeyframe + 1];
      float t = 0.0;
      if (elapsed > from.holdMs) {
        t = (float)(elapsed - from.holdMs) / from.fadeMs;
        t = t * t * (3.0 - 2.0 * t);  // ease in and out
      }
      for (int i = 0; i < 3; i++) {
        rgb[i] = (uint8_t)(from.color[i] + (to.color[i] - from.color[i]) * t);
      }
      break;
    }

    case JULY_LAUNCH: {
      // A faint, flickering glow that brightens as the rocket climbs
      float t = (float)elapsed / julyStageLength;
      float glow = 0.25 * t * (random(70, 101) / 100.0);
      // During the finale the previous burst is still fading underneath
      julyBurstLevel *= 0.94;
      for (int i = 0; i < 3; i++) {
        float launch = NIGHT_SKY[i] + (LAUNCH_GLOW[i] - NIGHT_SKY[i]) * glow;
        float lingering = NIGHT_SKY[i] + (julyBurstColor[i] - NIGHT_SKY[i]) * julyBurstLevel;
        rgb[i] = (uint8_t)max(launch, lingering);
      }
      if (elapsed >= julyStageLength) {
        memcpy(julyBurstColor, FIREWORK_COLORS[random(3)], 3);
        julyBurstLevel = 1.0;
        setJulyStage(JULY_BURST, now, 0);
      }
      break;
    }

    case JULY_BURST: {
      // Bright burst that fades, with crackling white glints as it dies
      if (elapsed > 60) {
        julyBurstLevel *= 0.94;
      }
      float crackle = 0.0;
      if (julyBurstLevel < 0.6 && random(100) < 25) {
        crackle = random(0, 50) / 100.0 * julyBurstLevel * 1.5;
      }
      for (int i = 0; i < 3; i++) {
        float burst = NIGHT_SKY[i] + (julyBurstColor[i] - NIGHT_SKY[i]) * julyBurstLevel;
        rgb[i] = (uint8_t)constrain(burst + (255 - burst) * crackle, 0, 255);
      }

      bool showOver = now - julyShowStart >= FIREWORKS_SHOW_MS;
      if (inFireworksFinale(now) && !showOver && julyBurstLevel < 0.35) {
        // Finale: the next rocket goes up before this one has faded
        launchFirework(now);
      } else if (julyBurstLevel < 0.03) {
        if (showOver) {
          // Show's over: back to red, white and blue
          julyKeyframe = 0;
          setJulyStage(JULY_COLORS, now, 0);
        } else {
          setJulyStage(JULY_GAP, now, random(250, 900));
        }
      }
      break;
    }

    case JULY_GAP:
      memcpy(rgb, NIGHT_SKY, 3);
      if (elapsed >= julyStageLength) {
        launchFirework(now);
      }
      break;
  }

  setColor(rgb);
}

void setup()  {
   // sets the pins as output
   pinMode(redPin, OUTPUT);
   pinMode(greenPin, OUTPUT);
   pinMode(bluePin, OUTPUT);

   setColor(initialColor);
   randomSeed(analogRead(A0));
   
   if (!BLE.begin()) {
      // Serial.println("* Starting Bluetooth® Low Energy module failed!");
      while (1);
   }

   // 20 characters max
   BLE.setLocalName("AquaTube (Playroom)");

   // Set the event listeners for characteristics
   colorWheelCharacteristic.setEventHandler(BLEWritten, onColorWheelWrite);
   colorCommandCharacteristic.setEventHandler(BLEWritten, onColorCommandWrite);

   BLE.setAdvertisedService(deviceService);
   
   // Add characteristics to the service
   deviceService.addCharacteristic(colorWheelCharacteristic);
   deviceService.addCharacteristic(colorCommandCharacteristic);

   // 20 characters max
   BLE.setDeviceName("AquaTube (Playroom)");
   BLE.addService(deviceService);
   BLE.advertise(); // Start advertising the service
}

void loop()  {
  BLE.poll();
  updateFirelight();
  updateStorms();
  updateChristmas();
  updateFourthOfJuly();
}
