/**
Some comment
*/

import processing.serial.*;
import cc.arduino.*;
Arduino arduino;

// an audio library that contains Minim, AudioInput, and some others
import ddf.minim.analysis.*;
import ddf.minim.*;

Minim minim;
/** in contains the data streaming to the audio input of the computer.
For laptops, this generally means the built-in mic. For desktops, this is the
input jack of the soundcard. There is no way for Java to change the audio input
so the user will have to do it externally to this program.

AudioInput contains three AudioBuffers: left, right and mix. left and right 
contain the information for the left and right speakers in a stereo setup. mix
contains the mix of the left and right samples. 
*/
AudioInput in;
FFT fft;

// Visualizer defaults
float valScale = 1.0;
float maxVisible = 10.0;
float beatThreshold = 0.25;
float colorOffset = 30;
float autoColorOffset = 0.01;

// Show text if recently adjusted
boolean showscale = false;
boolean showBeatThreshold = true;
boolean showHelp = false;

float beatH = 0;
float beatS = 0;
float beatB = 0;
float beatHprev = 0;
float arduinoBeatB = 0;
float arduinoBeatBprev = 0;

float[] lastY;
float[] lastVal;

int buffer_size = 1024;  // also sets FFT size (frequency resolution)
float sample_rate = 44100;

// The pins that the arduino uses to control the LEDs. These values would change
// depending on the configuration of the arduino.
int redPin = 2;
int greenPin = 3;
int bluePin = 4;
int redPin2 = 5;
int greenPin2 = 6;
int bluePin2 = 7;

boolean fullscreen = false;
int lastWidth = 0;
int lastHeight = 0;

boolean arduinoConnected = false;
int arduinoIndex = 2;
String arduinoMessage = "";

void setup() {

  // Sets the initial size of the window
  size(500, 300);
  // makes the window resizable
  frame.setResizable(true);
  
  // sets the background to black
  background(0);
  
  // 
  minim = new Minim(this);
  in = minim.getLineIn(Minim.MONO,buffer_size,sample_rate);
  
  fft = new FFT(in.bufferSize(), in.sampleRate());
  fft.logAverages(16, 2);
  fft.window(FFT.HAMMING);
  
  lastY = new float[fft.avgSize()];
  lastVal = new float[fft.avgSize()];
  initLasts();
  
  initArduino();
  
  textSize(10);
  
  frame.setAlwaysOnTop(true);
}

int leftBorder()   { return int(.05 * width); }
int rightBorder()  { return int(.05 * width); }
int bottomBorder() { return int(.05 * width); }
int topBorder()    { return int(.05 * width); }

void initArduino()
{
  String[] serialPorts;
  try {
    serialPorts = Arduino.list();
    arduinoIndex %= serialPorts.length;
  }
  catch (Exception e)
  {
    arduinoConnected = false;
    arduinoMessage = "Unable to list serial ports";
    println(e);
    return;
  }
  
  if(arduino != null)
  {
    arduino.dispose();
  }
  
  try {
    arduino = new Arduino(this, serialPorts[arduinoIndex], 57600);
    arduino.pinMode(redPin, Arduino.OUTPUT);
    arduino.pinMode(greenPin, Arduino.OUTPUT);
    arduino.pinMode(bluePin, Arduino.OUTPUT);
    arduino.pinMode(redPin2, Arduino.OUTPUT);
    arduino.pinMode(greenPin2, Arduino.OUTPUT);
    arduino.pinMode(bluePin2, Arduino.OUTPUT);
    arduinoConnected = true;
    arduinoMessage = "Connected on " +arduinoIndex + ":" + serialPorts[arduinoIndex];
    println(arduinoMessage);
  }
  catch (Exception e) {
    arduinoConnected = false;
    arduinoMessage = "Unable to connect on " +arduinoIndex + ":"+
      serialPorts[arduinoIndex] + "\nPress TAB to try a different port.";
    println(e);
  }
}

void initLasts()
{
  
  for(int i = 0; i < fft.avgSize(); i++) {
    lastY[i] = height - bottomBorder();
    lastVal[i] = 0;
  }
  
}

void draw() {
   
    colorMode(RGB);
  
    // Detect resizes
    if(width != lastWidth || height != lastHeight)
    {
      lastWidth = width;
      lastHeight = height;
      background(0);
      initLasts();
      println("resized");
    }
  
    // Slowly erase the screen
    fill(0,10 * 60/frameRate); // Based on 60fps
    rect(0,0,width,height - 0.8*bottomBorder());
  
    colorMode(HSB, 100);
  
    fft.forward(in.mix);
    smooth();
    noStroke();
    
    
    int iCount = fft.avgSize();
    float barHeight =  0.03*(height-topBorder()-bottomBorder());
    float barWidth = (width-leftBorder()-rightBorder())/iCount;
    
    float biggestValChange = 0;
    
    for(int i = 0; i < iCount; i++) {
      
      float iPercent = 1.0*i/iCount;
      
//      float highFreqscale = 1.0;
      float highFreqscale = 1.0 + pow(iPercent, 4) * 2.0;
      
      float val = sqrt(fft.getAvg(i)) * valScale * highFreqscale / maxVisible;
      
      float y = height - bottomBorder() - val * (height - bottomBorder() - topBorder());
      float x = leftBorder() + iPercent * (width - leftBorder() - rightBorder()) ;
      
      float h = 100 - (100.0 * iPercent + colorOffset) % 100;
      float s = 70 - pow(val, 3) * 70;
      float b = 100;
      
      fill(h, s, b);
      textAlign(CENTER, BOTTOM);
      text(nf(int(100*val),2), x+barWidth/2, y);
           
      rectMode(CORNERS);
      rect(x, y+barHeight/2, x+barWidth, lastY[i]+barHeight/2);
      
      float valDiff = val-lastVal[i];
      if(valDiff > beatThreshold && valDiff > biggestValChange)
      {
        biggestValChange = valDiff;
        beatH = h;
        beatS = s;
        beatB = b;
      }
      
      lastY[i] = y;
      lastVal[i] = val;

    }
    
    // If we've hit a beat, bring the brightness of the bar up to full
    if(biggestValChange > beatThreshold)
    {
      arduinoBeatB = constrain(biggestValChange * 100, 20, 100);
      beatThreshold = max(0.25, 0.8*biggestValChange);
    }  
    
    if (beatThreshold > 0.25) {
      beatThreshold -= 0.001;
    }
    if(abs(beatH - beatHprev) < 1) {
      beatH = beatHprev;
    }
    
    // calculate the arduino beat color
    color c_hsb = color(beatH, 100, constrain(arduinoBeatB, 20, 100));
    
      
    //color c_hsb = color(beatH, constrain(arduinoBeatB, 1, 100), 255);
    
    int r = int(red(c_hsb) / 100 * 255);
    int g = int(green(c_hsb) / 100 * 255);
    int b = int(blue(c_hsb) / 100 * 255);
   
    // clear out the message area
    fill(0);
    rect(0, height - 0.8*bottomBorder(), width, height);
    
    // draw the beat bar
    colorMode(RGB, 255);
    fill(r, g, b);
    rect(leftBorder(), height - 0.8*bottomBorder(), width-rightBorder(), height - .5*bottomBorder());

    // Decay the arduino beat brightness (based on 60 fps)
    arduinoBeatB *= 1.0 - 0.10 * 60/frameRate;
    // Tell the arduino to draw
    if (arduinoConnected)
    {
      try
      {
        if (abs(arduinoBeatBprev - arduinoBeatB) > 0.25) {//magic values!
        arduino.analogWrite(redPin, r);
        arduino.analogWrite(greenPin, g);
        arduino.analogWrite(bluePin, b);
        arduino.analogWrite(redPin2, r);
        arduino.analogWrite(greenPin2, g);
        arduino.analogWrite(bluePin2, b);
        }
        fill(16,16,16);
        textAlign(CENTER, BOTTOM);
        text(arduinoMessage, width/2, height);
      }
      catch (Exception e) {
        arduinoConnected = false;
        arduinoMessage = "Lost connection!  Press TAB to reconnect.";
        arduinoIndex--; // Pressing TAB advances, but we want to retry the same index
        println(e);
      }
    }
    else
    {
      fill(16);
      rect(0, topBorder()-15, width, topBorder()+15);
      
      fill(255,64,64);
      textAlign(CENTER, CENTER);
      text("Arduino error: " + arduinoMessage, width/2, topBorder());
    }

    
    
    // Automatically advance the color
    colorOffset += autoColorOffset;
    colorOffset %= 100;

    // Show the scale if it was adjusted recently
    if(showscale)
    {
      fill(255,255,255);
      textAlign(RIGHT, TOP);
      text("scale:"+nf(valScale,1,1), width-rightBorder(), topBorder());
      showscale=false;
    }
    
    // Show the beat threshold if it was adjusted recently
    if(showBeatThreshold)
    {
      fill(255,255,255);
      textAlign(RIGHT, TOP);
      text("beat threshold:"+nf(beatThreshold,1,2)+ " "+nf(biggestValChange, 1, 2)+ " "+nf(arduinoBeatB, 1, 2), width-rightBorder(), topBorder());
      showBeatThreshold=true;
    }
     
    // Show the help
    if(showHelp)
    {
      fill(255,255,255);
      textAlign(RIGHT, TOP);
      text("Help:\nUP/DOWN arrows = Scale Visualizer\n" + 
           "LEFT/RIGHT arrows = Temporarily shift colors\n" + 
           "+/- = Beat Detection Sensitivity\n" + 
           "TAB = Use Next Arduino Port\n" + 
           "SPACE = Toggle full-screen\n" + 
           "Anything Else = Show this help", width-rightBorder(), topBorder());
      showHelp=false;
    }
     
    // Display the frame rate
    fill(16, 16, 16);
    textAlign(RIGHT, BOTTOM);
    text(nf(frameRate,2,1) + " fps", width - rightBorder(), topBorder());
    if(!fullscreen)
    {
    frame.setTitle("This Is Your Brain On Music ("+nf(frameRate,2,1)+" fps)");
    }
    beatHprev = beatH;
    arduinoBeatBprev = arduinoBeatB;
  
}


void keyReleased()
{
  if (key == CODED)
  {
   if (keyCode == UP)
   {
     valScale += 0.1;
     showscale=true;
   }
   else if (keyCode == DOWN)
   {
     valScale -= 0.1;
     showscale = true;
   }
   else if (keyCode == RIGHT)
   {
     colorOffset -= 5;
   }
   else if (keyCode == LEFT)
   {
     colorOffset += 5;
   }
  }
  else
  {
    if (key == '+')
    {
      beatThreshold += 0.05;
      showBeatThreshold=true;
    }
    else if (key == '-')
    {
      beatThreshold -= 0.05;
      showBeatThreshold=true;
    }
    else if (key == ' ')
    {
      toggleFullScreen();
    }
    else if (key == TAB)
    {
      arduinoIndex++;
     initArduino(); 
    }
    else
    {
      showHelp = true;
    }
  } 
}

void keyPressed()
{
  
  // In fullscreen mode, capture ESC for exiting full screen
  if (key == ESC)
  {
   if(fullscreen)
   {
     toggleFullScreen(); 
     key=0;
   }
  }
}

void toggleFullScreen()
{
  fullscreen = !fullscreen;
  
  frame.removeNotify();
  frame.setUndecorated(fullscreen);
  if(fullscreen) {
    frame.setSize(displayWidth, displayHeight);
    frame.setLocation(0,0);
  }
  else
  {
    frame.setSize(500, 300);
    frame.setLocation(100,100);
  }
  frame.addNotify();
}

void stop()
{
  // always close Minim audio classes when you finish with them
  in.close();
  minim.stop();
 
  super.stop();
}
