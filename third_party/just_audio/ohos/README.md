# just_audio_ohos

https://pub.dev/packages/just_audio_ohos

Flutter is a feature rich audio player. Loop through various audio formats and play any sound from any source (asset/file/URL/stream) for seamless playback.

## Installation

First, add `just_audio_ohos` as a [dependency in your pubspec.yaml file](https://pub.dev/packages/just_audio_ohos).

```dart
flutter pub add just_audio_ohos
```

Next, import 'just_audio_ohos.dart' into your dart code.

```dart
import 'package:just_audio_ohos/just_audio_ohos.dart';
```

## Usage

```yaml
dependencies:
  just_audio: 0.9.37
  just_audio_ohos: 1.0.0
```

## Platform support

| Feature                        | Android | Ohos | iOS  | macOS | Web  | Windows | Linux |
| ------------------------------ | :-----: | :-----: | :--: | :---: | :--: | :-----: | :---: |
| read from URL                  |    ✅    |    ✅    |  ✅   |   ✅   |  ✅   |    ✅    |   ✅   |
| read from file                 |    ✅    |    ✅    |  ✅   |   ✅   |  ✅   |    ✅    |   ✅   |
| read from asset                |    ✅    |    ✅    |  ✅   |   ✅   |  ✅   |    ✅    |   ✅   |
| read from byte stream          |    ✅    |    ✅    |  ✅   |   ✅   |  ✅   |    ✅    |   ✅   |
| request headers                |    ✅    |    ✅    |  ✅   |   ✅   |      |    ✅    |   ✅   |
| DASH                           |    ✅    |    ✅    |      |       |      |    ✅    |   ✅   |
| HLS                            |    ✅    |    ✅    |  ✅   |   ✅   |      |    ✅    |   ✅   |
| ICY metadata                   |    ✅    |         |  ✅   |   ✅   |      |         |       |
| buffer status/position         |    ✅    |    ✅    |  ✅   |   ✅   |  ✅   |    ✅    |   ✅   |
| play/pause/seek                |    ✅    |    ✅    |  ✅   |   ✅   |  ✅   |    ✅    |   ✅   |
| set volume/speed               |    ✅    |    ✅    |  ✅   |   ✅   |  ✅   |    ✅    |   ✅   |
| clip audio                     |    ✅    |         |  ✅   |   ✅   |  ✅   |         |   ✅   |
| playlists                      |    ✅    |    ✅    |  ✅   |   ✅   |  ✅   |    ✅    |   ✅   |
| looping/shuffling              |    ✅    |    ✅    |  ✅   |   ✅   |  ✅   |    ✅    |   ✅   |
| compose audio                  |    ✅    |         |  ✅   |   ✅   |  ✅   |         |   ✅   |
| gapless playback               |    ✅    |    ✅    |  ✅   |   ✅   |      |    ✅    |   ✅   |
| report player errors           |    ✅    |    ✅    |  ✅   |   ✅   |  ✅   |    ✅    |   ✅   |
| handle phonecall interruptions |    ✅    |    ✅    |  ✅   |       |      |         |       |
| buffering/loading options      |    ✅    |    ✅    |  ✅   |   ✅   |      |         |       |
| set pitch                      |    ✅    |         |      |       |      |         |       |
| skip silence                   |    ✅    |         |      |       |      |         |       |
| equalizer                      |    ✅    |         |      |       |      |         |   ✅   |
| volume boost                   |    ✅    |         |      |       |      |         |   ✅   |

## Example

```dart
 import 'package:just_audio_ohos/just_audio_ohos.dart';

 final _player = AudioPlayer();
 await _player.setAudioSource(AudioSource.uri(Uri.parse(
    "https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3")));
	
 @override
 void dispose() {
    // Release decoders and buffers back to the operating system making them
    // available for other apps to use.
    _player.dispose();
    super.dispose();
 }
 
 SeekBar(
    duration: positionData?.duration ?? Duration.zero,
    position: positionData?.position ?? Duration.zero,
    bufferedPosition:
        positionData?.bufferedPosition ?? Duration.zero,
    onChangeEnd: _player.seek,
 );
 
 // Opens volume slider dialog
 IconButton(
   icon: const Icon(Icons.volume_up),
   onPressed: () {
     showSliderDialog(
       context: context,
       title: "Adjust volume",
       divisions: 10,
       min: 0.0,
       max: 1.0,
       value: player.volume,
       stream: player.volumeStream,
       onChanged: player.setVolume,
     );
   },
 ),

 /// This StreamBuilder rebuilds whenever the player state changes, which
 /// includes the playing/paused state and also the
 /// loading/buffering/ready state. Depending on the state we show the
 /// appropriate button or loading indicator.
 StreamBuilder<PlayerState>(
   stream: player.playerStateStream,
   builder: (context, snapshot) {
     final playerState = snapshot.data;
     final processingState = playerState?.processingState;
     final playing = playerState?.playing;
     if (processingState == ProcessingState.loading ||
         processingState == ProcessingState.buffering) {
       return Container(
         margin: const EdgeInsets.all(8.0),
         width: 64.0,
         height: 64.0,
         child: const CircularProgressIndicator(),
       );
     } else if (playing != true) {
       return IconButton(
         icon: const Icon(Icons.play_arrow),
         iconSize: 64.0,
         onPressed: player.play,
       );
     } else if (processingState != ProcessingState.completed) {
       return IconButton(
         icon: const Icon(Icons.pause),
         iconSize: 64.0,
         onPressed: player.pause,
       );
     } else {
       return IconButton(
         icon: const Icon(Icons.replay),
         iconSize: 64.0,
         onPressed: () => player.seek(Duration.zero),
       );
     }
   },
 ),
 // Opens speed slider dialog
 StreamBuilder<double>(
   stream: player.speedStream,
   builder: (context, snapshot) => IconButton(
     icon: Text("${snapshot.data?.toStringAsFixed(1)}x",
         style: const TextStyle(fontWeight: FontWeight.bold)),
     onPressed: () {
       showSliderDialog(
         context: context,
         title: "Adjust speed",
         divisions: 10,
         min: 0.5,
         max: 1.5,
         value: player.speed,
         stream: player.speedStream,
         onChanged: player.setSpeed,
       );
     },
   ),
 ),
```