//
//  ViewController.swift
//  audioFFT
//
//  Created by Anjiss on 1/26/16.
//  Copyright © 2016 Anjiss. All rights reserved.
//

import UIKit
import AVFoundation
import Accelerate


class ViewController: UIViewController, AVAudioRecorderDelegate {
    
    @IBOutlet weak var lableHz: UILabel!
    
    var audioRecorder: AVAudioRecorder!
    var audioFile: AVAudioFile!
    var timer = NSTimer()
    var audioData = [Float]()
    var fftSamples: Int = 0
    var sampleRate: Double = 0
    var fftOutput = [Float]()
    let recordSettings = [AVSampleRateKey : NSNumber(float:Float(44100.0)), AVFormatIDKey : NSNumber(int: Int32(kAudioFormatAppleLossless)), AVNumberOfChannelsKey : NSNumber(int:1), AVEncoderAudioQualityKey : NSNumber(int: Int32(AVAudioQuality.Max.rawValue)), AVEncoderBitRateKey : 320000]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        lableHz.text = "preparing..."
        let audioSession = AVAudioSession.sharedInstance()
        do{
            try audioSession.setCategory(AVAudioSessionCategoryRecord)
            try audioRecorder = AVAudioRecorder(URL:self.directoryURL()!, settings: recordSettings)
        } catch {}
        timer = NSTimer.scheduledTimerWithTimeInterval(0.5, target: self, selector: "update", userInfo: nil, repeats: true)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func update (){
        if !audioRecorder.recording {
            let audioSession = AVAudioSession.sharedInstance()
            audioRecorder.prepareToRecord()
            do {
                try audioSession.setActive(true)
                audioRecorder.record()
            } catch {print("wrong when start record")}
            
        } else {
            audioRecorder.stop()
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setActive(false)
                try audioFile = AVAudioFile(forReading: audioRecorder.url)
            } catch {print("wrong when stop record")}
            
            let result = fft(audioRecorder.url)
            print("file length: " + String(audioFile.length))
            lableHz.text = String(result) + " Hz"
        }
        
    }
    
    func directoryURL() -> NSURL?{
        let fileManager = NSFileManager.defaultManager()
        let urls = fileManager.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
        let documentDirectory = urls[0] as NSURL
        let soundURL = documentDirectory.URLByAppendingPathComponent("sound.caf")
        return soundURL
    }
    
    func fft(audioUrl: NSURL) -> Int {
        var af = ExtAudioFileRef()
        var err: OSStatus = ExtAudioFileOpenURL(audioUrl as CFURL, &af)
        guard err == noErr else {
            fatalError("1")
        }
        
        //allocate an empty ASBD
        var fileASBD = AudioStreamBasicDescription()
        
        //get the ASBD from the file
        var size = UInt32(sizeofValue(fileASBD))
        err = ExtAudioFileGetProperty(af, kExtAudioFileProperty_FileDataFormat, &size, &fileASBD)
        guard err == noErr else {
            fatalError("2")
        }
        
        if sampleRate == 0 {
            sampleRate = fileASBD.mSampleRate
        }
        
        var clientASBD = AudioStreamBasicDescription()
        clientASBD.mSampleRate = sampleRate
        clientASBD.mFormatID = kAudioFormatLinearPCM
        clientASBD.mFormatFlags = kAudioFormatFlagIsFloat
        clientASBD.mBytesPerPacket = 4
        clientASBD.mFramesPerPacket = 1
        clientASBD.mBytesPerFrame = 4
        clientASBD.mChannelsPerFrame = 1
        clientASBD.mBitsPerChannel = 32
        
        //set the ASBD to be used
        err = ExtAudioFileSetProperty(af, kExtAudioFileProperty_ClientDataFormat, size, &clientASBD)
        guard err == noErr else {
            fatalError("3")
        }
        
        //check the number of frames expected
        var numberOfFrames: Int64 = 0
        var propertySize = UInt32(sizeof(Int64))
        err = ExtAudioFileGetProperty(af, kExtAudioFileProperty_FileLengthFrames, &propertySize, &numberOfFrames)
        guard err == noErr else {
            fatalError("4")
        }
        
        //initialize a buffer and a place to put the final data
        let bufferFrames = 4096
        let finalData = UnsafeMutablePointer<Float>.alloc(Int(numberOfFrames) * sizeof(Float.self))
        defer {
            finalData.dealloc(Int(numberOfFrames) * sizeof(Float.self))
        }
        
        //pack all this into a buffer list
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(sizeof(Float.self) * bufferFrames),
                mData: finalData
            )
        )
        
        //read the data
        var count: UInt32 = 0
        var ioFrames: UInt32 = 4096
        while ioFrames > 0 {
            err = ExtAudioFileRead(af, &ioFrames, &bufferList)
            
            guard err == noErr else {
                fatalError("5")
            }
            count += ioFrames
            
            bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(sizeof(Float.self) * bufferFrames),
                    mData: finalData + Int(count)
                )
            )
            
        }
        
        audioData = Array(UnsafeMutableBufferPointer(start: finalData, count: Int(numberOfFrames) * sizeof(Float.self)))
        //dispose of the file
        err = ExtAudioFileDispose(af)
        guard err == noErr else {
            fatalError("6")
        }
        
        //fft operations
        let frames = 44100
        
        let fft_length = vDSP_Length(log2(CDouble(frames)))
        print("fft_length"+String(fft_length))
        let setup = vDSP_create_fftsetup(fft_length, Int32(kFFTRadix2))
        if setup == nil {
            fatalError("Could not setup fft")
        }
        
        let outReal = UnsafeMutablePointer<Float>.alloc(Int(frames/2) * sizeof(Float.self))
        defer {
            outReal.dealloc(Int(frames/2) * sizeof(Float.self))
        }
        let outImag = UnsafeMutablePointer<Float>.alloc(Int(frames/2) * sizeof(Float.self))
        defer {
            outImag.dealloc(Int(frames/2) * sizeof(Float.self))
        }
        
        var out = COMPLEX_SPLIT(realp: outReal, imagp: outImag)
        var dataAsComplex = UnsafePointer<COMPLEX>(finalData)
        
        vDSP_ctoz(dataAsComplex, 2, &out, 1, UInt(frames/2))
        vDSP_fft_zip(setup, &out, 1, fft_length, Int32(FFT_FORWARD))
        
        let power = UnsafeMutablePointer<Float>.alloc(Int(frames) * sizeof(Float.self))
        defer {
            power.dealloc(Int(frames) * sizeof(Float.self))
        }
        
        for i in 0..<frames/2 {
            power[i] = sqrt(outReal[i] * outReal[i] + outImag[i] * outImag[i])
            if isnan(power[i]) {
                fatalError("7")
            }
        }
        
        fftOutput = Array(UnsafeMutableBufferPointer(start: power, count: Int(frames/2)))
        
        var find = 0
        var max : Float = 0.0
        for i in 0..<frames{
            if power[i]>max{
                max = power[i]
                find = i
            }
        }
        find = Int(Double(find)/1.48595)
        if find > 7210{
            find = frames/2 - find
        }
        print("HZ: " + String(find))
        //var outputAF = ExtAudioFileRef()
        //let docsPath = "/Users/mike/Desktop/"
        //let filePath = docsPath.stringByAppendingString("file.wav")
        //let outputURL = NSURL(fileURLWithPath: filePath)
        //err = ExtAudioFileCreateWithURL(outputURL, kAudioFileCAFType, &clientASBD, nil, AudioFileFlags.EraseFile.rawValue, &outputAF)
        //guard err == noErr else {
        //    fatalError("1unhelpful error code is \(err)")
        //}
        //var outputBufferList = AudioBufferList(
        //    mNumberBuffers: 1,
        //    mBuffers: AudioBuffer(
        //        mNumberChannels: 1,
        //        mDataByteSize: UInt32(sizeof(Float.self) * Int(numberOfFrames)),
        //        mData: finalData
        //    )
        //)
        //err = ExtAudioFileWrite(outputAF, UInt32(numberOfFrames), &outputBufferList)
        //guard err == noErr else {
        //    fatalError("2unhelpful error code is \(err)")
        //}

        return find
    }
}

