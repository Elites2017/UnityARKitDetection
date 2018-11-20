////////////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2018, richardstech
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of
//  this software and associated documentation files (the "Software"), to deal in
//  the Software without restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
//  Software, and to permit persons to whom the Software is furnished to do so,
//  subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
//  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
//  PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
//  OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

//	Original header below.

///////////////////////////////////////////////////////////////////////////////
// ARRectangleExample.cs
// 
// Author: Adam Hegedus
// Contact: adam.hegedus@possible.com
// Copyright © 2018 POSSIBLE CEE. Released under the MIT license.
///////////////////////////////////////////////////////////////////////////////

using System.Linq;
using Possible.Vision.Managed;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.XR.iOS;
using Utils;
using Possible.Vision.Managed.Bridging;

namespace DetectionApp
{
	public class Detection : MonoBehaviour 
	{
		[SerializeField] private Vision _vision;

		// max number of objects to be detected

		int objCount = 10;
	
		private GameObject[] _markerArray;

		private GameObject _detectionPrimitive;

		private void Awake()
		{
			// We need to tell the Vision plugin what kind of requests do we want it to perform.
			// This call not only prepares the managed wrapper for the specified image requests,
			// but allocates VNRequest objects on the native side. You only need to call this
			// method when you initialize your app, and later if you need to change the type
			// of requests you want to perform. 
			// maxObservations refers to the maximum number of rectangles allowed to be recognized at once.
			_vision.SetAndAllocateRequests(VisionRequest.Classification, maxObservations: objCount);

			_markerArray = new GameObject[objCount];
			_detectionPrimitive = GameObject.Find ("Detection");
			_detectionPrimitive.SetActive (false);
		}
			
		private void OnEnable()
		{
			_vision.OnObjectClassified += Vision_OnObjectClassified;
		
			// Hook up to ARKit's frame update callback to be able to get a handle to the latest pixel buffer
			UnityARSessionNativeInterface.ARFrameUpdatedEvent += UnityARSessionNativeInterface_ARFrameUpdatedEvent;
		}

		private void OnDisable()
		{
			_vision.OnObjectClassified -= Vision_OnObjectClassified;
			UnityARSessionNativeInterface.ARFrameUpdatedEvent -= UnityARSessionNativeInterface_ARFrameUpdatedEvent;
		}
	
		private void UnityARSessionNativeInterface_ARFrameUpdatedEvent(UnityARCamera unityArCamera)
		{

#if !UNITY_EDITOR && UNITY_IOS
// Evaluate the current state of ARKit's pixel buffer for recognizable objects
// We only classify a new image if no other vision requests are in progress
        if (!_vision.InProgress)
        {
            // This is the call where we pass in the handle to the image data to be analysed
            _vision.EvaluateBuffer(
                
                // This argument is always of type IntPtr, that refers the data buffer
                buffer: unityArCamera.videoParams.cvPixelBufferPtr,
                
                // We need to tell the plugin about the nature of the underlying data.
                // The plugin only supports CVPixelBuffer (CoreVideo) and MTLTexture (Metal).
                // The ARKit plugin uses CoreVideo to capture images from the device camera.
                dataType: ImageDataType.CoreVideoPixelBuffer);
        }
#endif
		}
	
		private void Vision_OnObjectClassified(object sender, ClassificationResultArgs e)
		{
			// Display the top guess for the dominant object on the image

			bool[] foundArray = new bool[objCount];
			for (int i = 0; i < objCount; i++)
				foundArray [i] = false;

			int index = -1;
			foreach (VisionClassification obs in e.observations) {

				// Ignore detections with low confidence

				if (obs.confidence < 0.65)
					continue;

				index++;
				string name = obs.identifier.Split(',')[0];

				// create the Detection GameObject if necessary

				if (_markerArray [index] == null) {
					_markerArray [index] = GameObject.Instantiate<GameObject>(_detectionPrimitive);
				} 

				// Need to convert the box factors to be centered around 0
				// The DetectionRectangle is going to be 1m from the camera so in fact
				// these percentages become coordinates.

				float xMin = (obs.xMin - 0.5f); 
				float yMin = (obs.yMin - 0.5f); 
				float xMax = (obs.xMax - 0.5f); 
				float yMax = (obs.yMax - 0.5f);

				// The center of the box is needed for the GameObject lcoal position

				float xCenter = (xMax - xMin) / 2 + xMin;
				float yCenter = -((yMax - yMin) / 2 + yMin);

				// The primitive plane GameObject is 10 x 10 so the width (which will beused as the
				// local scale for the plane) has to be divided by 10

				float width = (xMax - xMin) / 10.0f;
				float height = (yMax - yMin) / 10.0f;

				Debug.Log ("Got: " + index + ", " + name + " " + obs.confidence +" " + obs.xMin + " " + obs.yMin + " " + obs.xMax + " " + obs.yMax +
					"/n" + "Center: " + xCenter + ", " + yCenter + " size: " + width + ", " + height);

				Vector3 pos = new Vector3 (xCenter, yCenter, 0);

				// Set the correct data in the child GameObjects

				_markerArray [index].GetComponentInChildren<DetectionRectangle> ().SetData (pos, width, height);
				_markerArray [index].GetComponentInChildren<DetectionName> ().SetData (pos, name);

				foundArray[index] = true;
			}
			for (int i = 0; i < objCount; i++) {
				if (_markerArray[i] != null) {
					// Hide the marker if the index is unused or show if it is used
					_markerArray[i].gameObject.SetActive (foundArray[i]);
				}	
			}				
		}

		void Update()
		{
			for (int index = 0; index < objCount; index++) {
				if (_markerArray [index] != null) {

					// set the correct position and rotation. Position is 1m in front of the camera.

					_markerArray [index].gameObject.transform.position = Camera.main.transform.position + Camera.main.transform.forward * 1;
					_markerArray [index].gameObject.transform.rotation = Camera.main.transform.rotation; 
				}
			}
		}			
	}
}
