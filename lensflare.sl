/****************************************************************************
 * lensflare.sl
 *
 * Description: This shader, when placed on a piece of geometry 
 *   immediately in front of the camera, simulates lens flare.
 *   These effects happen in real cameras when the camera points toward
 *   a bright light source, resulting in interreflections within the
 *   optical elements of the lens system itself.  Real lens flare is
 *   pretty plain looking and uninteresting; this shader takes some
 *   liberties but looks pretty good.
 *   
 * Parameters:
 *   intensity - overall scale of intensity of all lens flare effects
 *   bloomintensity - overall intensity of the "bloom" effect.  Setting
 *          this to 0 removes the bloom effect altogether.
 *   bloomradius, bloomfalloff - control the size & shape of the bloom
 *   bloomstarry, bloomnpoints - control the "starry" appearance of the 
 *          bloom effect (bloomstarry=0 means perfectly round bloom)
 *   starburstintensity - overall intensity of starburst effect (0=none)
 *   starburstradius, starburstnpoints, starburstfalloff - control the
 *          size and shape of the starburst effect
 *   rainbowintensity - intensity of rainbow effect (0=none)
 *   rainbowradius, rainbowwidth - size of the rainbow
 *   nspots - number of "spots" splayed out on the axis joining the
 *          image center with the light position
 *   disky, ringy, blotty, bloony - give the relative proportions of
 *          the 4 different kinds of spots.
 *   spotintensity - overall intensity scale for the spots
 *   spotvarycolor - scale the color variation of the spots
 *   seed - random number seed for many of the computations
 *
 * WARNING: lens flare is notorious as a sign of cheesy, cheap computer
 *   graphics.  Use this effect with extreme care!  
 *
 ***************************************************************************
 *
 * Author: Larry Gritz & Tony Apodaca, 1999
 *
 * Contacts:  lg@pixar.com
 *
 * $Revision: 1.1 $    $Date: 2000/08/28 01:30:35 $
 *
 ****************************************************************************/
 /*
 * Ported from Renderman Shader to OSL: Dylan Whiteman, 2013
 * 
 * Many thanks to the above authors for the amazing OSL.
 * Many thanks to the Blender team for an amazing 3D tool.
 *
 * Apologies to the above authors for any degradation or errors to the original code.
 *
 * See You-Tube Video Tutorials for use of this shader:
 * - LensFlare Tutorial Part 1 of 4: Blender Real TIme Lens Flare Shader Introduction: 
 *   http://youtu.be/Whbq8H6Ltvk
 *
 * - LensFlare Tutorial: Part 2 of 4: How To Set Up a LensFlare Shader in Blender 
 *   http://youtu.be/mf69t-hKxVk
 *
 * 
 * Dylan's Notes: 
 *  - Tested  with Blender's 'Cycles' render engine. 
 *  - Added:    -  Input: Light Position (x, y, z) world co-ordinates. The flare bloom is centred on this position.
 *                 (as OSL does not support "illuminance (P, vector "camera" (0,0,1), PI/2)") 
 *              -  Output: Cbloom, CstarBurst, Craonbow and Cring elements for greater user control.
 *              -  Comments for OSL newbies like myself.
 *        
 *  - Blender Usage:
 *      Overview:
 *      -   Create a plane to sit in front of the camera. Parent the plane to the camera.
 *      -   Give the  plane  a material with this shader's composite output feeding an emission shader.
 *          Add the emission shader to a transparent shader. The sum feeds the material's Surface input.
 *      -   Feed the 'source' lamp x,y,z position into this shader using 3 Value Input nodes and an RGB combiner node.
 *      -   Use Blender 'Drivers' to get the lamp x,y,z positions into their respective Value input nodes.
 *      -   To save render time, create a Render Layer with just the parented plane present. 
 *          Set this Render Layer's "Samples:" override setting to 1 (only one sample is needed) .
 *      
 *      Step by Step:
 *      1) Create a plane with (approx.) the same aspect ratio as  the render setting. Give the plane a name. e.g lensFlarePlane
 *      2) Align the plane with the camera view. The plane should fill the camera view
 *      3) Parent the plane to the camera. The plane should now always stay in the same position relative to the camera frame.
 *      4) Create a node based material for the lensFlarePlane. Add and connect the following nodes:
 *      5)      Connect an Emission shader and a Transparent shader to an Add shader.
 *      6)      Connect the Add shader output to the Surface input of the Material Output node.
 *      7)      Create a Script node and select this lensflare.osl file as the script.
 *      7b)     Note: The "Open Shader" check box must be ticked in the Render (camera icon) settings in the Properties panel
 *      8)      Press the Compile/Update button on the script node. All the input and output nodes should appear.
 *              If the script does not compile - check step 7b. Check that the patterns.h file is present.
 *      9)      Connect the Composite output node of the lensFlare01 shader to the Color input of the Emission shader.
 *      10)     Create a Combine RGB node. Conect the Image output of this node to the LightPos input of the lensFlare01 shader.
 *      11)     Create an Input Value node. Connect the Value output to the R input of the Combine RGB node.
 *      12)     Create an Input Value node. Connect the Value output to the G input of the Combine RGB node.
 *      13)     Create an Input Value node. Connect the Value output to the B input of the Combine RGB node.
 *      14) The three Value input nodes just created will be used to pass the x,y,z world position of the lens-flare 
 *          light source to the lens-flare shader. "Drivers" must be added to the 'x,y,z' Value input nodes for the 
 *          lens-flare bloom to be automatically placed in the correct position on the screen.
 *          ... to be continued
 *      
 *               
 ****************************************************************************/

//#include "patterns.h"
#include "stdosl.h"
#define PI M_PI

/* Helper function: compute the aspect ratio of the frame */
float aspectratio ()
{
    point Pcorner0 = transform ("NDC", "screen", point(0,0,0));
    point Pcorner1 = transform ("NDC", "screen", point(1,1,0));
    float ar = (Pcorner1[0]-Pcorner0[0]) /(Pcorner1[1]-Pcorner0[1]);
    return ar;
}


// From patterns.h by Larry Gritz. Copied here so users don't have to save
// header files into the osl search path.

float filteredpulse (float edge0, float edge1, float x, float dx)
{
    float x0 = x - dx/2;
    float x1 = x0 + dx;
    return max (0, (min(x1,edge1)-max(x0,edge0)) / dx);
}

/* The filterwidthp macro is similar to filterwidth, but is for 
 * point data. */
 /* Define metrics for estimating filter widths, if none has already
 * been defined.  This is crucial for antialiasing.
 */
#ifndef MINFILTWIDTH
#  define MINFILTWIDTH 1.0e-6
#endif

float filterwidthp(point p) 
  {return (float)max (sqrt(area(p)), MINFILTWIDTH);}




/* Helper function: compute the camera's diagonal field of view */
float cameradiagfov ()
{
    vector corner = vector (transform("NDC","camera",point(1,1,0)));
    float halfangle = acos (dot(normalize(corner), vector(0,0,1)))/2;
    return halfangle;
}

// return 0 if u or v is out side the range 0 to 1
// return 1 otherwise.
int uvInbounds(float u, float v)
{
    if (u < 0.0) return 0;
    if (u > 1.0) return 0;

    if (v < 0.0) return 0;
    if (v > 1.0) return 0;
    else return 1;
}


color rainbow (float x, float dx)
{
#define R	color(1,0,0)
#define O	color(1,.5,0)
#define Y	color(1,1,0)
#define G	color(0,1,0)
#define B	color(0,0,1)
#define Ii	color(.375,0,0.75)
#define V	color(0.5,0,0.5)
    // color rb = spline ("linear",x, V,V,Ii,B,G,Y,O,R,R);
    
    // Looks like we have to use an array for the moment in OSL
    color s[10];
    s[0] = V; 
    s[1] = V;
    s[2] = Ii;
    s[3] = Ii;
    s[4] = B;
    s[5] = G;
    s[6] = Y;
    s[7] = O;
    s[8] = R;
    s[9] = R;
    color rb = spline ("linear",x,s);
    float p = filteredpulse (0, 1, x, dx) ;   
    return rb * p;
}



shader lensflare01 ( 
        vector LightPosition = vector(1.8,6.3,0.6),
        color LightColor = color(.52,.52,.52),
        float AspectRatio = 0.0,
        float intensity = 1.0,
        int seed = 143,

        string bloomImg= "//textures/flares/bloom.png",
        float bloomImageMix = 0.0,
	    float bloomintensity = 0.1,
	    float bloomradius = 1.4,
	    float bloomstarry = 0.5,
	    float bloomnpoints = 50,
	    float bloomfalloff = 5.7,

        string starBurstImg = "//textures/flares/starBurst.png",
        float starBurstImageMix = 0.0,
	    float starburstintensity = 0.101,
	    float starburstradius = 0.8,
	    float starburstnpoints = 50,
	    float starburstfalloff = 7.1,

        string rainbowImg = "//textures/flares/rainbow.png",
        float rainBowImageMix = 0.0,
	    float rainbowintensity = 0.009,
	    float rainbowradius = 0.55,
	    float rainbowwidth = 0.7,

        string spots_diskImg = "//textures/flares/hexDisk.png",
        string spots_ringImg = "//textures/flares/hexRing.png",
        string spots_blotImg = "//textures/flares/hexBlot.png",
        string spots_blotHoleImg = "//textures/flares/hexHoley.png",
        float spotsImageMix = 0.0,
	    float spotintensity = 0.15,
        float spotRadius = 1.0,
	    float spotvarycolor = 1.5,
	    int nspots = 50,
	    int disky = 3,
	    int ringy = 3,
	    int blotty = 3,
	    int holey = 3,

        output closure color LensFlare_EmissionShader = 0,
        output color CLensFlare_ColorShader = color(0),   // All lens flare elements composited
        output color CLensFlare_synthOnly = color(0),     // The color outputs below allow 
        output color CLensFlare_imgOnly= color(0),        // fine tuning in the material node editor or compositor
        
        output color Cbloom_synth = color(0),             // Just the synthesised bloom
        output color CstarBurst_synth= color(0),          // Just the synthesised starburst
        output color Crainbow_synth = color(0),           // Just the synthesised rainbow
        output color CspotAll_synth = color(0),             // Just the synthesised combined rings (disk, ring, blot,holowblot)
        
        output color Cbloom_img = color(0),               // Just the image based bloom
        output color CstarBurst_img = color(0),           // Just the image based starburst
        output color Crainbow_img = color(0),             // Just the image based rainbow
        output color CspotAll_img = color(0),               // Just the image based combined rings (disk, ring, blot,holowblot)
        
                                                          // Having access to individual rings allows fine tuning in material node editor or compositor
        output color Cspot_disk_only = color(0),               // Just the combined disk (synth + image)
        output color Cspot_ring_only = color(0),               // Just the combined ring (synth + image)
        output color Cspot_blot_only = color(0),               // Just the combined blot (synth + image)
        output color Cspot_hole_only = color(0)                // Just the combined holowblot (synth + image)
    )
{
     // Generate repeatable sequences of 'random' numbers - based on nrand and seed settings.
     float nrand = 0;
          
     // Random helper function
     float urand () {
	       nrand += 1; 
	       return cellnoise(nrand, seed);
     } 
     
    point LightPos = LightPosition;
    
    float aspect = AspectRatio;
    // If the user has not defined the aspect ration -- then calculate it based
    // on the screen dimensions. NOTE: In Blender this works well when rendering, however
    // when the aspect ration calculated for the 3D preview viewport  does not match the render window
    // calculations UNLESS the 3D preview viewport is sized by the user. Hence -- it can pay to set this by hand.
    // Also -- defining the AspectRation manually allows for anamorphic lens flare effects.
    if (AspectRatio == 0){
        aspect = abs(aspectratio());
    }
    
    
    float lensfov = cameradiagfov();
    
    // illuminance (P, vector "camera" (0,0,1), PI/2);  // renderman function.
    // dw: In OSL we need get our light source info from the LightPos input connection to the node.
    // (GetAttributes does not seem to work as we'd like in Cyles at time of writing).
    
    // Transform the center of the screen (.5,.5,0) in NDC to common (world) coords for later light 
    // position calcs also in common  coords.
    point camPos= transform("NDC","common",point(.5,.5,0));
    
    // L is the vector from the cam to the flare light source in  common (world) coordinates
    // We need it to calculate how bright the flare should be for this cam to light angle.
    vector L = LightPos - camPos;  
    // Ldir is the lens flare axis vector in cam coords.     
    vector Ldir =  normalize(transform("camera", L));
    // Attenuate the lens flare effect as the flare source leaves the camera field of view.
    float atten = 1 - smoothstep( 1, 2, abs(acos(Ldir[2])) / (lensfov/2) );
    float brightness = atten * intensity *(LightColor[0]+LightColor[1]+LightColor[2])/3;
    
    // Position of point being shaded in normalised device coordinates. 
    // 0,0,0 = top left screen. 1,1,0 = bot right screen in NDC
    // Now the screen range is (-1-1,0) top left to (1,1) top right
    // (0,0,0) is in centre of the screen - with z axis pointing in camera direction
    point Pndc = (transform("common","NDC", P) - vector (.5, .5, 0))*2;
    
    // The actual screen is (most likely) rectangular - so extend the range of the x axis to taking into account the
    // aspect ration. This way, 'drawing'  that is done in these 'normalise' coordinates (e.g circles) won't be stretched
    // when we transform back to common or world space. Let's call this NDCa coords.
    Pndc *= vector(aspect, 1, 0);
    
    // dPndc needed for antialiasing.(investigate details wrt cycles implementation later)
    float dPndc = filterwidthp(Pndc);
    
    // Calculate the flare source light position in NDCa  coords.
    // Normalised coords make it easier to use step functions - as the bottom right of the screen
    // is always (aspect,1) for all render sizes.
	point Plight = (transform("common","NDC", LightPos) - vector (.5, .5, 0))*2;
	Plight *= vector(aspect, 1, 0);
	
    // Calculate the distance and angle from the point being shaded to the lens-flare axis.
    // The distance and angle from the lens-flare axis determine what shade the pixel will be coloured.
	vector Lvec = Plight - Pndc;                       // lensflare axis vector = lightpos - shadePos  (in 'NDC' coords)
	float dist = length(Lvec);                         // dist of the pixel bring shaded to the lens flare axis in 'NDC' coords
	float angle = atan2(Lvec[1], Lvec[0]) + PI;        // angle of the lens-flare axis

    float alpha = 1.0;
    
	
    /*
	 * Handle the image of the lamp.  There are 3 effects:
	 * the bloom, a small red ring flare, and the triple starburst.
	 */


    /* Bloom */
	if (bloomintensity > 0) {
	    float radius = sqrt(brightness)*5*mix(.2, bloomradius, urand());
	    float bloom = pnoise (bloomnpoints*angle/(2*PI), bloomnpoints);
	    bloom = mix (0.5, bloom, bloomstarry);
	    bloom = mix (1, bloom, smoothstep(0, 0.5, dist/radius));
	    bloom = pow(1-smoothstep(0.0, radius*bloom, dist),bloomfalloff);
	    Cbloom_synth+= bloom * (bloomintensity) / brightness;

        point uv = ((Pndc -  Plight)/(2*radius))+point(.5,.5,0);
        int useImg = uvInbounds(uv[0],uv[1]);

        if (bloomImageMix && useImg){
            Cbloom_img = texture(bloomImg, uv[0], 1.0 - uv[1], "alpha", alpha) *
                (bloomintensity) / brightness;
            CLensFlare_imgOnly += Cbloom_img;
        }
	}

	/* Starburst */
	if (starburstintensity > 0) {
	    float radius = sqrt(brightness)*5*mix(.2, starburstradius, urand());
	    float star = pnoise (starburstnpoints*angle/(2*PI),starburstnpoints);
	    star = pow(1-smoothstep(0.0, radius*star, dist), starburstfalloff);
	    CstarBurst_synth += star * (starburstintensity) / brightness;

        point uv = ((Pndc -  Plight)/(2*radius))+point(.5,.5,0);
        int useImg = uvInbounds(uv[0],uv[1]);

        if (starBurstImageMix && useImg){
            point uv = ((Pndc -  Plight)/(2*radius))+point(.5,.5,0);
            CstarBurst_img = texture(starBurstImg, uv[0], 1.0 - uv[1], "alpha", alpha) *
                (starburstintensity) / brightness;
            CLensFlare_imgOnly += CstarBurst_img;
        }
	}

	/* Rainbow */
	if (rainbowintensity > 0) {
	    Crainbow_synth += brightness*(rainbowintensity / intensity)
		* rainbow((dist/rainbowradius-1)/rainbowwidth,
			  (dPndc/rainbowradius)/rainbowwidth);

        point uv = ((Pndc -  Plight)/(2*rainbowradius+rainbowwidth))+point(.5,.5,0);
        int useImg = uvInbounds(uv[0],uv[1]);

        if (rainBowImageMix && useImg){
            Crainbow_img = texture(rainbowImg, uv[0], 1.0 - uv[1], "alpha", alpha) *
                (rainbowintensity) / brightness;
            CLensFlare_imgOnly +=  Crainbow_img;
        }
	}

	/*
	 * Now emit the random rings themselves
	 */
        
    // We will move up and down the lens flare axis  vector- placing rings, spots along the way
    vector axis = normalize(Plight);
	float i;

    // Every time this shader is called (i.e for every pixel) -- the same sequence of random
    // numbers (with the resulting random rings etc) will be generated. Set nrand to achieve this
	nrand = 20;   /* Reset on purpose! */
    float synth_intensity = 0;
    color img_intensity = color(0);

	for (i = 0; i < nspots; i += 1) {
        synth_intensity = 0;
        img_intensity = color(0);
	    // (re)generate the 'stats' for this ith spot.
        float alongaxis = urand();
	    point cntr = point (mix(-2, 1, alongaxis) * axis);

        // Calculate the position of this ring along the lensflare axis, and the ring's radius.
	    float axisdist = distance (cntr, Pndc);
	    float radius = mix (.08, .3,pow(urand(),2)) * spotRadius * distance(cntr,Plight);

        // generate UV co-ords that can select the pixel to draw when an image texture is used to draw the spots. 
        point uv = ((Pndc -  cntr)/(2*radius))+point(.5,.5,0); 
        float alpha = 1.0;
        
        // Check to see if the uv coordinated are outside the image texture plane. (0 = out of bounds)
        // This is used to speed up drawing. No need to access texture co-ords for out of bounds uv.
        // There is also no need to access texture co-ords if the user does not want to use textures for their spots
        int useImg = uvInbounds(uv[0],uv[1]);
        if  (spotsImageMix ==0) useImg = 0;
              
        // Calculate the color and brightness of this spots pixel
	    color clr = LightColor; 
	    clr *=  1+ spotvarycolor * color ((cellnoise(i) - 0.5), 0,0);
	    float bright = 1 - (2 * radius);
	    bright *= bright;

        color spotBaseColor = spotintensity * bright * clr * LightColor;

        // Like playing cards in a deck - the user has defined how many disk, ring, blot and hole
        // type 'cards' there are in each deck
	    float alltypes = (disky+ringy+blotty+holey);
        
        // Choose a card type from the deck. It is essential thatt his 'random' choice repeats in the same (exact) sequence
        // every time we go through the 'for' loop below.
	    float type = urand()*alltypes;


        // Choose the spot shading method based on the 'card' choice.
	    if (type < disky) { 
          // Flat disk  
          // dw changed from filterstep for OSL compilation. Look at changing back later.
		  synth_intensity = 1 - smoothstep(radius, axisdist-dPndc/2,axisdist+dPndc/2); 
          
          if (useImg) {img_intensity = texture(spots_diskImg, uv[0], 1.0 - uv[1], "alpha", alpha);}
          Cspot_disk_only +=  spotBaseColor * mix(synth_intensity,img_intensity, spotsImageMix);
	    } 
        else if (type < (disky+ringy)) {  
          // Ring 
		  synth_intensity = filteredpulse (radius, radius+0.05*axisdist,axisdist, dPndc);                         // entirely synthesised disk spot
          if (useImg) {img_intensity = texture(spots_ringImg, uv[0], 1.0 - uv[1], "alpha", alpha);}               // disk spot from an image
	      Cspot_ring_only +=  spotBaseColor * mix(synth_intensity,img_intensity, spotsImageMix);                  // allow the user (output) access to all ring spots
        } 
        else if (type < (disky+ringy+blotty)) {  
          // Soft spot 
		  synth_intensity = 1 - smoothstep (0, radius, abs(axisdist));
          if (useImg) {img_intensity = texture(spots_blotImg, uv[0], 1.0 - uv[1], "alpha", alpha);}
          Cspot_blot_only +=  spotBaseColor * mix(synth_intensity,img_intensity, spotsImageMix);                  // allow the user (output) access to all blot spots .. etc
	    } 
        else {   
          // Spot with soft hole in middle 
		  synth_intensity = smoothstep(0, radius, axisdist) - smoothstep(radius, axisdist-dPndc/2, axisdist+dPndc/2);
          if (useImg) {img_intensity = texture(spots_blotHoleImg, uv[0], 1.0 - uv[1], "alpha", alpha);}
	      Cspot_hole_only +=  spotBaseColor * mix(synth_intensity,img_intensity, spotsImageMix);  
        }
        
        // Provide the user with all the spot types composited together. Offer the synth output as well as an image based output.
        CspotAll_synth += spotBaseColor * synth_intensity; 
        if (useImg) CspotAll_img += spotBaseColor * img_intensity;
	}

    // Output the composite of all effects.
        CLensFlare_synthOnly = Cbloom_synth + CstarBurst_synth + Crainbow_synth + CspotAll_synth;
        CLensFlare_imgOnly += CspotAll_img;
    
    if (CLensFlare_imgOnly != 0 ) {
        // only mix in the image flare elements if they exist (speed up)
        CLensFlare_ColorShader = mix(Cbloom_synth,Cbloom_img, bloomImageMix) +
                                    mix(CstarBurst_synth,CstarBurst_img, starBurstImageMix) +
                                        mix(Crainbow_synth,Crainbow_img, rainBowImageMix) +
                                            mix(CspotAll_synth,CspotAll_img, spotsImageMix);
    }
    else
    {
        // There are no image based flare elemnts -- so the output contains only the synthesised elements
        CLensFlare_ColorShader = Cbloom_synth + CstarBurst_synth + Crainbow_synth + CspotAll_synth;
    }
    
    float brightAdj = atten* intensity;
    CLensFlare_synthOnly *= brightAdj;
    CLensFlare_imgOnly  *= brightAdj;  //CLensFlare_synthOnly
    Cspot_disk_only *= brightAdj;
    Cspot_ring_only *= brightAdj;
    Cspot_blot_only *= brightAdj;
    Cspot_hole_only *= brightAdj;
    CLensFlare_ColorShader *= brightAdj;
    
    LensFlare_EmissionShader = CLensFlare_ColorShader * emission() + transparent();
}