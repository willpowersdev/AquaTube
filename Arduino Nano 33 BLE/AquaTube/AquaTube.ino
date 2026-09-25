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
const uint8_t COMMAND_DEFAULT_COLOR = 5;

// Firelight routine state. The routine drifts toward a random target
// "heat" (red -> orange) and brightness, then picks a new target.
bool firelightActive = false;
float fireHeat = 0.5;         // 0 = deep red, 1 = bright orange
float fireBrightness = 0.8;   // 0..1
float fireTargetHeat = 0.5;
float fireTargetBrightness = 0.8;
float fireEase = 0.2;          // how quickly we move toward the target
unsigned long fireNextTargetAt = 0;
unsigned long fireLastFrameAt = 0;
const unsigned long FIRE_FRAME_MS = 15;

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
    case COMMAND_DEFAULT_COLOR:
      stopRoutines();
      setColor(0, 128, 255);
    break;
  }
}

void stopRoutines() {
  firelightActive = false;
  stormsActive = false;
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

// Maps heat (0 = deep red, 1 = bright orange) and brightness to an LED color.
// Green falls off faster than red as the flame dims, so dim flames look
// redder like real embers. Keep in sync with FirelightPreview in the iOS app.
void setFireColor(float heat, float brightness) {
  float red = 255.0 * brightness;
  float green = (18.0 + heat * 112.0) * brightness * brightness;
  setColor((uint8_t)red, (uint8_t)green, 0);
}

void pickFireTarget() {
  long roll = random(100);
  if (roll < 8) {
    // Occasional gutter: the flame dips low and red
    fireTargetHeat = random(0, 25) / 100.0;
    fireTargetBrightness = random(25, 45) / 100.0;
    fireEase = 0.35;
    fireNextTargetAt = millis() + random(60, 140);
  } else if (roll < 20) {
    // Occasional flare: a quick bright orange lick
    fireTargetHeat = random(80, 100) / 100.0;
    fireTargetBrightness = random(92, 100) / 100.0;
    fireEase = 0.45;
    fireNextTargetAt = millis() + random(40, 100);
  } else {
    // Normal flicker around a warm red-orange
    fireTargetHeat = random(30, 75) / 100.0;
    fireTargetBrightness = random(60, 92) / 100.0;
    fireEase = random(8, 25) / 100.0;
    fireNextTargetAt = millis() + random(50, 220);
  }
}

void startFirelight() {
  stopRoutines();
  firelightActive = true;
  fireHeat = 0.5;
  fireBrightness = 0.75;
  fireLastFrameAt = 0;
  pickFireTarget();
}

// Non-blocking so BLE.poll() keeps running between frames
void updateFirelight() {
  if (!firelightActive) {
    return;
  }

  unsigned long now = millis();
  if (now - fireLastFrameAt < FIRE_FRAME_MS) {
    return;
  }
  fireLastFrameAt = now;

  if ((long)(now - fireNextTargetAt) >= 0) {
    pickFireTarget();
  }

  fireHeat += (fireTargetHeat - fireHeat) * fireEase;
  fireBrightness += (fireTargetBrightness - fireBrightness) * fireEase;

  // A little per-frame jitter keeps it from looking like smooth fades
  float jitter = random(-4, 5) / 100.0;
  setFireColor(fireHeat, constrain(fireBrightness + jitter, 0.0, 1.0));
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
    stormNextEventAt = now + random(2500, 12000);
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
}
