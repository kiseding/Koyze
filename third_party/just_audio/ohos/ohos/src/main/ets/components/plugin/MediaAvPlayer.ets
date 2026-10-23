/**
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 * */

import { media } from '@kit.MediaKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AVCastPickerState, avSession } from '@kit.AVSessionKit';
import MediaSource from './MediaSource';
import { fileIo } from '@kit.CoreFileKit';
import { MethodResult } from '@ohos/flutter_ohos';

const TAG = 'MediaAvPlayer';
const OPERATE_ERROR: number = 801;
const AVPLAYER_STATE_ERROR: number = 5400102;
const AVPLAYER_IO_ERROR: number = 5400103;

enum AudioPlayerState {
  IDLE,
  INITIALIZED,
  LOAD,
  PREPARED,
  PLAY,
  PAUSE,
  STOP,
  ERROR,
  COMPLETED,
  RELEASED,
  PROGRESS_SPEED,
  TIME_UPDATE,
  VOLUME_CHANGE,
  UNKNOWN
}

export enum LoopMode {
  DEFAULT,
  SINGLE_CYCLE,
  LIST_LOOP
}

enum SeekMode {
  UNKNOWN,
  SEEK,
  FINISH
}

export enum PlaybackState {
  STATE_READY, STATE_BUFFERING, STATE_ENDED
}

export interface onChangeMediaAvPlayerState {
  onPlaybackStateChanged(state: PlaybackState): void;

  onUpdateCurrentIndex(updateIndex: number): void;

  onUpdatePosition(updatePosition: number): void;

  onUpdateBufferedPosition(bufferedPosition: number): void;

  onAudioSessionIdChanged(audioSessionId: number): void;

  broadcastImmediatePlaybackEvent(): void;

  completeSeek(): void;

  completeInitial(): void;

  onStartBuffering(): void;

  onEndBuffering(): void;

  setAudioSessionId(audioSessionId: number): void
}

export class MediaAvPlayer {
  private context: common.UIAbilityContext | undefined = AppStorage.get('context');
  public avPlayer: media.AVPlayer | null = null;
  public avPlayerNext: media.AVPlayer | null = null;
  public isPlaying: boolean = false;
  public songList: MediaSource[] = [];
  public state: AudioPlayerState = AudioPlayerState.IDLE;
  private session?: avSession.AVSession;
  private initialPos: number = -1;
  private initialIndex: number = -1;
  private volume: number = -1;
  private speed: number = 1;
  private speedAppliedForCurrentSource: boolean = false;
  private seekModule: SeekMode = SeekMode.UNKNOWN;
  private playMode: LoopMode = LoopMode.DEFAULT;
  private isFirst: boolean = true;
  private isPrepared: boolean = false;
  private isClipping: boolean = false;
  private isPreBuffering: boolean = false;
  private isRandom: boolean = false;
  private musicIndex: number = 0;
  private preMusicIndex: number = 0;
  private songItem: MediaSource | null = null;
  private shuffleOrder: number[] = [];
  private avMetadataExtractor: media.AVMetadataExtractor | null = null;
  private avMetadata?: media.AVMetadata;
  private mediaAvPlayerStateChangeListener?: onChangeMediaAvPlayerState;
  private pendingPlayResult: MethodResult | null = null;
  private initialization: Promise<void> = Promise.resolve();
  private isDisposed: boolean = false;
  // 播放策略
  private playStrategy: media.PlaybackStrategy = {
    //播放策略首选宽度，int类型，如1080。
    preferredWidth: 1,
    //播放策略首选高度，int类型，如1920。
    preferredHeight: 2,
    //播放策略首选缓冲持续时间，单位s，取值范围1-20。
    // 在线音乐默认预留 5 秒，降低弱网下 AVPlayer 反复欠载的概率。
    preferredBufferDuration: 5,
    //播放策略true是hdr，false非hdr，默认非hdr。
    preferredHdr: false
  };

  constructor() {
    this.initialization = this.initAudioPlayer();
  }

  setMediaAvPlayerStateChange(listener: onChangeMediaAvPlayerState) {
    this.mediaAvPlayerStateChangeListener = listener
  }

  /**
   * 获取MediaAvPlayer实例
   * */
  public static getInstance(): MediaAvPlayer {
    let mediaAvPlayer: MediaAvPlayer | undefined = AppStorage.get('mediaService');
    if (!mediaAvPlayer) {
      mediaAvPlayer = new MediaAvPlayer();
      AppStorage.setOrCreate('mediaService', mediaAvPlayer);
    }
    return mediaAvPlayer;
  }

  private playCall: () => void = async () => {
    console.info(TAG, `on play , do play task`);
    if (this.isFirst) {
      await this.loadAssent(0);
    } else {
      this.play();
    }
  };
  private pauseCall: () => void = () => {
    console.info(TAG, `on pause , do pause task`);
    this.pause();
  };
  private playNextCall: () => void = () => {
    console.info(TAG, `on playNext , do playNext task`);
    this.playNextAuto();
  };
  private playPreviousCall: () => void = () => {
    console.info(TAG, `on playPrevious , do playPrevious task`);
    this.playPrevious();
  };
  /**
   * 异常监听
   * */
  private errorCall: (err: BusinessError) => void = (err: BusinessError) => {
    if (err.code == OPERATE_ERROR || err.code == AVPLAYER_STATE_ERROR || err.code == AVPLAYER_IO_ERROR) {
      console.error(TAG, `AvPlayer Avoid Error Reporting: ${err}`);
      return;
    }
    console.error(TAG, `Invoke avPlayer failed, code is ${err.code}, message is ${err.message}`);
    this.loadAssent(this.musicIndex);
  };
  /**
   * 缓冲回调
   * */
  private bufferingUpdate: (infoType: media.BufferingInfoType, value: number) =>
  void = (infoType: media.BufferingInfoType, value: number) => {
    switch (infoType) {
      case media.BufferingInfoType.CACHED_DURATION:
        this.mediaAvPlayerStateChangeListener?.onUpdateBufferedPosition(value);
        break;
      case media.BufferingInfoType.BUFFERING_START:
        this.mediaAvPlayerStateChangeListener?.onStartBuffering();
        break;
      case media.BufferingInfoType.BUFFERING_PERCENT:
        if (value < 100) {
          this.mediaAvPlayerStateChangeListener?.onStartBuffering();
        } else if (this.seekModule != SeekMode.SEEK) {
          this.mediaAvPlayerStateChangeListener?.onEndBuffering();
        }
        break;
      case media.BufferingInfoType.BUFFERING_END:
        if (this.seekModule != SeekMode.SEEK) {
          this.mediaAvPlayerStateChangeListener?.onEndBuffering();
        }
        break;
    }
  }
  /**
   * 下一曲缓冲回调
   * */
  private bufferingUpdateNext: (infoType: media.BufferingInfoType, value: number) =>
  void = (_infoType: media.BufferingInfoType, _value: number) => {
  }
  /**
   * 监听资源播放当前时间，单位为毫秒（ms），用于刷新进度条当前位置，默认间隔100ms时间上报，因用户操作(seek)产生的时间变化会立刻上报
   * */
  private updateTimeCall: (updateTime: number) => void = (updateTime: number) => {
    if (this.volume != -1) {
      this.avPlayer?.setVolume(this.volume);
      this.volume = -1;
    }
    if (this.isClipping) {
      if (this.avPlayer && updateTime > 0 && this.getDuration() > 0 &&
        (this.songItem!.getEndUs() / 1000) < updateTime) {
        this.seek(this.playMode != LoopMode.SINGLE_CYCLE ? this.avPlayer.duration :
          (this.songItem!.getStartUs() / 1000));
      }
    }
  };
  /**
   * 进度条拖动回调,拖动松手后不会立刻回调,完成后回调
   * */
  private seekCall: (seekDoneTime: number) => void = async (seekDoneTime: number) => {
    this.mediaAvPlayerStateChangeListener?.completeSeek();
    this.seekModule = SeekMode.FINISH;
    if (this.state == AudioPlayerState.PREPARED || this.state == AudioPlayerState.PLAY ||
      this.state == AudioPlayerState.PAUSE || this.state == AudioPlayerState.COMPLETED) {
      this.playingState();
    }
    console.info(TAG, `AVPlayer seek succeeded, seek time is ${seekDoneTime}`);
  };
  /**
   *订阅录制状态机AVRecorderState切换的事件，当 AVRecorderState状态机发生变化时，会通过订阅的回调方法通知用户。用户只能订阅一个状态机切换事件的回调方法，当用户重复订阅时，以最后一次订阅的回调接口为准
   * */
  private stateCall: (state: string) => Promise<void> = async (state: string) => {
    switch (state) {
      case 'idle':
        console.info(TAG, 'AVPlayer state idle called.');
        this.state = AudioPlayerState.IDLE;
        if (this.avPlayerNext == null) {
          this.offAVPlayerNextCallback();
          this.preMusicIndex = this.musicIndex + 1;
          let nextSong: MediaSource = this.songList[this.preMusicIndex];
          if (this.musicIndex == this.songList.length - 1) {
            if (this.playMode == LoopMode.LIST_LOOP) {
              this.preMusicIndex = 0;
              nextSong = this.songList[this.preMusicIndex];
            }
          }
          if (this.isRandom && this.shuffleOrder.length == this.songList.length) {
            let currentIndex = this.shuffleOrder.indexOf(this.musicIndex);
            if (currentIndex != -1) {
              if (currentIndex == this.shuffleOrder.length - 1) {
                this.preMusicIndex = this.shuffleOrder[0];
              } else {
                this.preMusicIndex = this.shuffleOrder[currentIndex+1];
              }
              nextSong = this.songList[this.preMusicIndex];
            }
          }
          if (nextSong) {
            media.createAVPlayer().then((value: media.AVPlayer) => {
              this.avPlayerNext = value;
              this.setAVPlayerNextCallback();
              let nextUrl = nextSong.getUri();
              if (nextUrl && this.avPlayerNext.state == "idle") {
                this.loadUri(this.avPlayerNext, nextUrl);
              }
            });
          }
        }
        break;
      case 'initialized':
        console.info(TAG, 'AVPlayer state initialized called.');
        this.state = AudioPlayerState.INITIALIZED;
        if (this.avPlayer) {
          this.avPlayer.prepare().then(() => {
            console.info(TAG, 'AVPlayer prepare succeeded.');
          }, (err: BusinessError) => {
            console.error(TAG, `Invoke prepare failed, code is ${err.code}, message is ${err.message}`);
          });
        }
        break;
      case 'prepared':
        this.state = AudioPlayerState.PREPARED;
        this.isPrepared = true;
        this.isPreBuffering = false;
        this.applySpeedIfNeeded();
        console.info(TAG, 'AVPlayer prepared .');
        // TIME_UNSET is a large negative value; only non-negative positions are real seeks.
        if (this.initialPos >= 0 && this.initialIndex >= 0 && this.initialIndex == this.musicIndex) {
          this.seek(this.initialPos);
          this.initialPos = -1;
          this.initialIndex = -1;
          this.mediaAvPlayerStateChangeListener?.completeInitial();
          this.mediaAvPlayerStateChangeListener?.onPlaybackStateChanged(PlaybackState.STATE_READY);
          break;
        }
        if (this.isClipping) {
          this.avPlayer?.seek(this.songItem!.getStartUs() / 1000);
          this.mediaAvPlayerStateChangeListener?.onPlaybackStateChanged(PlaybackState.STATE_BUFFERING);
          break;
        }
        this.playingState();
        this.avMetadata = await this.avMetadataExtractor?.fetchMetadata();
        this.setAVMetadata();
        break;
      case 'playing':
        console.info(TAG, 'AVPlayer state playing called.');
        this.isPlaying = true;
        this.state = AudioPlayerState.PLAY;
        this.mediaAvPlayerStateChangeListener?.onEndBuffering();
        break;
      case 'paused':
        console.info(TAG, 'AVPlayer state paused called.');
        this.state = AudioPlayerState.PAUSE;
        this.completePendingPlay();
        break;
      case 'completed':
        console.info(TAG, 'AVPlayer state completed called.');
        this.state = AudioPlayerState.COMPLETED;
        const playbackEnded =
          (this.playMode == LoopMode.DEFAULT && this.musicIndex == this.songList.length - 1) ||
          this.songList.length == 0;
        if (playbackEnded) {
          this.completePendingPlay();
          this.mediaAvPlayerStateChangeListener?.onPlaybackStateChanged(PlaybackState.STATE_ENDED);
        }
        this.playNextAuto();
        break;
      case 'stopped':
        console.info(TAG, 'AVPlayer state stopped called.');
        this.state = AudioPlayerState.STOP;
        this.completePendingPlay();
        break;
      case 'released':
        console.info(TAG, 'AVPlayer state released called.');
        this.state = AudioPlayerState.RELEASED;
        break;
      default:
        console.info(TAG, 'AVPlayer state unknown called.');
        this.state = AudioPlayerState.UNKNOWN;
        this.loadAssent(this.musicIndex)
        break;
    }
  };
  /**
   *订阅录制状态机AVRecorderState切换的事件，当 AVRecorderState状态机发生变化时，会通过订阅的回调方法通知用户。用户只能订阅一个状态机切换事件的回调方法，当用户重复订阅时，以最后一次订阅的回调接口为准
   * */
  private preStateCall: (state: string) => Promise<void> = async (state: string) => {
    switch (state) {
      case 'idle':
        console.info(TAG, 'avPlayerNext state idle called.');
        break;
      case 'initialized':
        console.info(TAG, 'avPlayerNext state initialized called.');
        this.avPlayerNext?.prepare().then(() => {
        }, (err: BusinessError) => {
          console.error(TAG, `avPlayerNext Invoke prepare failed, code is ${err.code}, message is ${err.message}`);
        });
        break;
      case 'prepared':
        if (this.isPreBuffering) {
          this.isPreBuffering = false;
          this.applySpeedIfNeeded();
          this.playingState();
        }
        console.info(TAG, 'avPlayerNext state prepared ');
        break;
      case 'playing':
        console.info(TAG, 'avPlayerNext state playing called.');
        break;
      case 'paused':
        console.info(TAG, 'avPlayerNext state paused called.');
        break;
      case 'completed':
        console.info(TAG, 'avPlayerNext state completed called.');
        break;
      case 'stopped':
        console.info(TAG, 'avPlayerNext state stopped called.');
        break;
      case 'released':
        console.info(TAG, 'avPlayerNext state released called.');
        this.avPlayerNext = null;
        break;
      default:
        console.info(TAG, 'avPlayerNext state unknown called.');
        break;
    }
  };

  playingState() {
    if (this.isPlaying) {
      const player = this.avPlayer;
      if (player == null) {
        return;
      }
      const playResult = this.pendingPlayResult;
      player.play().then(() => {
        if (this.avPlayer === player && this.isPlaying) {
          console.info(TAG, 'AVPlayer play succeeded.');
          this.mediaAvPlayerStateChangeListener?.onPlaybackStateChanged(PlaybackState.STATE_READY);
        }
      }, (err: BusinessError) => {
        console.error(TAG, `Invoke play failed, code is ${err.code}, message is ${err.message}`);
        this.completePendingPlayWithError(player, playResult, err);
      });
    } else if (this.avPlayer?.state == 'prepared' || this.avPlayer?.state == 'paused') {
      this.mediaAvPlayerStateChangeListener?.onPlaybackStateChanged(PlaybackState.STATE_READY);
    }
  }

  private completePendingPlay() {
    const playResult = this.pendingPlayResult;
    if (playResult != null) {
      playResult.success(new Map<String, Object>());
      this.pendingPlayResult = null;
    }
  }

  private completePendingPlayWithError(
    player: media.AVPlayer,
    playResult: MethodResult | null,
    err: BusinessError
  ) {
    if (this.avPlayer !== player ||
      playResult == null || this.pendingPlayResult !== playResult) {
      return;
    }
    playResult.error(err.code.toString(), err.message, err.data);
    this.pendingPlayResult = null;
  }

  setAVPlayerNextCallback() {
    this.avPlayerNext?.on('stateChange', this.preStateCall);
    this.avPlayerNext?.on('bufferingUpdate', this.bufferingUpdateNext);
  }

  offAVPlayerNextCallback() {
    this.avPlayerNext?.off('stateChange', this.preStateCall);
    this.avPlayerNext?.off('bufferingUpdate', this.bufferingUpdateNext);
  }

  setListenerForMesFromController() {
    if (!this.session) {
      return;
    }
    this.session.on('play', this.playCall);
    this.session.on('pause', this.pauseCall);
    this.session.on('playNext', this.playNextCall);
    this.session.on('playPrevious', this.playPreviousCall);
  }

  /**
   * 为服务设置回调监听
   * */
  private setAVPlayerCallback() {
    if (!this.avPlayer) {
      return;
    }
    this.avPlayer.on('seekDone', this.seekCall);

    this.avPlayer.on('error', this.errorCall);

    this.avPlayer.on('timeUpdate', this.updateTimeCall);

    this.avPlayer.on('bufferingUpdate', this.bufferingUpdate);

    this.avPlayer.on('stateChange', this.stateCall);

  }

  /**
   * 为服务注销回调监听
   * */
  private offAVPlayerCallback() {
    if (!this.avPlayer) {
      return;
    }
    this.avPlayer.off('seekDone', this.seekCall);

    this.avPlayer.off('error', this.errorCall);

    this.avPlayer.off('timeUpdate', this.updateTimeCall);

    this.avPlayer.off('bufferingUpdate', this.bufferingUpdate);

    this.avPlayer.off('stateChange', this.stateCall);

  }

  /**
   * Play previous music.
   */
  public playPrevious() {
    switch (this.playMode) {
      case LoopMode.LIST_LOOP:
      case LoopMode.DEFAULT:
        if (this.isRandom) {
          this.playRandom();
          break;
        }
        if (this.musicIndex === 0) {
          this.updateMusicIndex(this.songList.length - 1);
        } else {
          this.updateMusicIndex(this.musicIndex - 1);
        }
        this.loadAssent(this.musicIndex);
        break;
      default:
        break;
    }
  }

  private updateMusicIndex(musicIndex: number) {
    this.mediaAvPlayerStateChangeListener?.onUpdateCurrentIndex(musicIndex)
    if (this.musicIndex !== musicIndex) {
      this.musicIndex = musicIndex;
    }
    if (this.session !== undefined) {
      this.setAVMetadata();
    }
  }

  async setAVMetadata() {
    let id = this.musicIndex;
    try {
      let metadata: avSession.AVMetadata = {
        assetId: `${id}`,
        title: this.avMetadata?.title ?? "未知",
        artist: this.avMetadata?.artist ?? "未知",
        mediaImage: this.avMetadata?.albumArtist,
        duration: this.getDuration()
      };
      if (this.session) {
        this.session.setAVMetadata(metadata).then(() => {
          console.info(TAG, 'SetAVMetadata successfully');
        }).catch((err: BusinessError) => {
          console.error(TAG, `SetAVMetadata BusinessError: code: ${err.code}, message: ${err.message}`);
        });
      }
    } catch (error) {
      console.error(TAG,
        `SetAVMetadata try: code: ${(error as BusinessError).code},message: ${(error as BusinessError).message}`);
    }
  }

  public getDuration() {
    if (this.isPrepared && this.avPlayer) {
      if (this.isClipping && this.songItem) {
        let duration = this.songItem.getEndUs() - this.songItem.getStartUs();
        return duration / 1000;
      }
      return this.avPlayer.duration;
    }
    return 0;
  }

  public setLoopMode(loopMode: number) {
    this.playMode = loopMode;
  }

  public setShuffleMode(isShuffle: boolean) {
    this.isRandom = isShuffle;
  }

  public setVolume(volume: number) {
    this.volume = volume
    this.avPlayer?.setVolume(volume);
  }

  private applySpeedIfNeeded() {
    const player = this.avPlayer;
    if (!this.speedAppliedForCurrentSource && player?.state == 'prepared') {
      player.setSpeed(this.speed);
      this.speedAppliedForCurrentSource = true;
    }
  }

  public setSpeed(speed: number) {
    if (speed > 0 && speed <= 0.125) {
      //x0.125
      this.speed = 9;
    } else if (speed > 0.125 && speed <= 0.4) {
      //x0.25
      this.speed = 8;
    } else if (speed > 0.4 && speed <= 0.6) {
      //x0.5
      this.speed = 5;
    } else if (speed > 0.6 && speed <= 0.8) {
      //x0.75
      this.speed = 0;
    } else if (speed > 0.8 && speed <= 1.1) {
      //x1
      this.speed = 1;
    } else if (speed > 1.1 && speed <= 1.4) {
      //x1.25
      this.speed = 2;
    } else if (speed > 1.4 && speed <= 1.6) {
      //x1.5
      this.speed = 6;
    } else if (speed > 1.6 && speed <= 1.8) {
      //x1.75
      this.speed = 3;
    } else if (speed > 1.8 && speed <= 2.0) {
      //x2.0
      this.speed = 4;
    } else if (speed > 2.0) {
      //由于2.0~3.0中间没有枚举速率,并且速率最大值为3.0,,所以大于2.0的速率都将映射到3.0x速度
      this.speed = 7;
    }

    const player = this.avPlayer;
    if (player?.state == 'prepared' || player?.state == 'playing' ||
      player?.state == 'paused') {
      player.setSpeed(this.speed);
      this.speedAppliedForCurrentSource = true;
    } else {
      this.speedAppliedForCurrentSource = false;
    }
  }

  /**
   * 初始化音频播放器
   * */
  async initAudioPlayer(): Promise<void> {
    const player = await media.createAVPlayer();
    if (this.isDisposed) {
      player.release();
      return;
    }
    this.avPlayer = player;
    this.avMetadataExtractor = await media.createAVMetadataExtractor();
    if (this.isDisposed) {
      this.avMetadataExtractor?.release();
      this.avMetadataExtractor = null;
      player.release();
      this.avPlayer = null;
      return;
    }
    this.setAVPlayerCallback();
    // AVSession setup is independent from the AVPlayer readiness barrier.
    this.createSession();
  }

  async createSession() {
    if (!this.context) {
      return;
    }
    this.session = await avSession.createAVSession(this.context, 'SESSION_NAME', 'audio');
    this.session.activate();
    this.setAVMetadata();
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: this.context.abilityInfo.bundleName,
          abilityName: this.context.abilityInfo.name
        }
      ],
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    wantAgent.getWantAgent(wantAgentInfo).then((agent) => {
      if (this.session) {
        this.session.setLaunchAbility(agent);
      }
    })
    this.mediaAvPlayerStateChangeListener?.setAudioSessionId(parseInt(this.session.sessionId))
    this.setListenerForMesFromController();
  }

  /**
   * Play music.
   */
  public async play(result?: MethodResult) {
    await this.initialization;
    if (this.isDisposed) {
      result?.error('player_unavailable', 'AVPlayer is unavailable', null);
      return;
    }
    this.isPlaying = true;
    if (result != null) {
      this.pendingPlayResult?.success(new Map<String, Object>());
      this.pendingPlayResult = result;
    }
    const player = this.avPlayer;
    if (player == null) {
      this.pendingPlayResult?.error('player_unavailable', 'AVPlayer is unavailable', null);
      this.pendingPlayResult = null;
      return;
    }
    if (player.state == 'playing') {
      this.pendingPlayResult?.success(new Map<String, Object>());
      this.pendingPlayResult = null;
    } else if (player.state == 'prepared' || player.state == 'paused' || player.state == 'completed') {
      this.isPrepared = true;
      this.playingState();
    }
  }

  /**
   * Pause music.
   */
  public async pause(result?: MethodResult) {
    await this.initialization;
    this.pendingPlayResult?.success(new Map<String, Object>());
    this.pendingPlayResult = null;
    const player = this.avPlayer;
    if (!this.isPlaying || player == null) {
      this.isPlaying = false;
      result?.success(new Map<String, Object>());
      return;
    }
    this.isPlaying = false;
    player.pause().then(() => {
      if (this.avPlayer === player) {
        this.state = AudioPlayerState.PAUSE;
        this.updateIsPlay(false);
      }
      result?.success(new Map<String, Object>());
    }).catch((e: BusinessError) => {
      result?.error(e.code.toString(), e.message, e.data)
      console.error(TAG, "pause::error" + e.message);
    });
  }

  /**
   * Play next music.
   *
   * @param isFromControl
   */
  public playNextAuto() {
    switch (this.playMode) {
      case LoopMode.SINGLE_CYCLE:
        if (this.avPlayer) {
          this.avPlayer.loop = true;
          this.loadAssent(this.musicIndex)
        }
        break;
      case LoopMode.LIST_LOOP:
      case LoopMode.DEFAULT:
        if (this.avPlayer) {
          this.avPlayer.loop = false;
        }
        if (this.isRandom) {
          this.playRandom();
        } else {
          this.playNext();
        }
        break;
      default:
        break;
    }
  }

  /**
   * Play music by index.
   *
   * @param musicIndex
   */
  async loadAssent(musicIndex: number) {
    await this.initialization;
    if (this.isDisposed || this.avPlayer == null) {
      return;
    }
    if (this.seekModule == SeekMode.SEEK) {
      this.seekModule = SeekMode.UNKNOWN;
    }
    if (musicIndex >= this.songList.length) {
      musicIndex = this.songList.length - 1;
      console.error(TAG, `current musicIndex ${musicIndex}`);
      return;
    }
    this.mediaAvPlayerStateChangeListener?.onUpdateBufferedPosition(0);
    this.mediaAvPlayerStateChangeListener?.onPlaybackStateChanged(PlaybackState.STATE_BUFFERING);
    this.speedAppliedForCurrentSource = false;
    this.isPrepared = false;
    this.songItem = this.songList[musicIndex];
    this.isClipping = this.songItem.type == "clipping";
    this.updateMusicIndex(musicIndex);
    if (this.avPlayerNext && this.preMusicIndex == musicIndex && !this.isFirst) {
      this.offAVPlayerCallback();
      this.offAVPlayerNextCallback();
      this.avPlayer?.release();
      this.avPlayer = this.avPlayerNext;
      this.setAVPlayerCallback();
      if (this.avPlayer?.state == 'prepared') {
        this.isPrepared = true;
        this.applySpeedIfNeeded();
        this.playingState();
      } else {
        this.isPrepared = false;
        this.isPreBuffering = true;
      }
      this.avPlayerNext = null;
    } else {
      if (this.avPlayer) {
        this.avPlayerNext = null;
        if (this.isFirst) {
          this.isFirst = false;
        } else {
          await this.avPlayer.reset();
        }
        let url = this.songItem?.getUri();
        if (url && this.avPlayer.state == "idle") {
          this.loadUri(this.avPlayer, url);
        }
      }
    }
  }

  async dispose() {
    this.isDisposed = true;
    this.pendingPlayResult?.success(new Map<String, Object>());
    this.pendingPlayResult = null;
    this.avPlayer?.release();
    this.avPlayerNext?.release();
    this.avMetadataExtractor?.release();
    this.avMetadataExtractor = null;
    this.avPlayerNext = null;
    this.avPlayer = null;
  }

  private playNext() {
    if (this.musicIndex === this.songList.length - 1) {
      if (this.playMode == LoopMode.LIST_LOOP) {
        this.loadAssent(0);
      }
    } else {
      this.loadAssent(this.musicIndex + 1);
    }
  }

  private playRandom() {
    if (this.shuffleOrder.length == 0) {
      let num = Math.round(Math.random() * (this.songList.length - 1));
      if (this.musicIndex === num) {
        this.playRandom();
      } else {
        this.updateMusicIndex(num);
        this.loadAssent(num);
      }
    } else {
      let orderIndex = this.shuffleOrder.indexOf(this.musicIndex);
      let num = orderIndex == this.shuffleOrder.length - 1 ? 0 : orderIndex + 1;
      this.updateMusicIndex(this.shuffleOrder[num]);
      this.loadAssent(this.shuffleOrder[num]);
    }
  }

  /**
   * Seek play music.
   *
   * @param ms.
   */
  public seek(ms: number, index?: number) {
    this.mediaAvPlayerStateChangeListener?.onStartBuffering();
    if (ms == this.avPlayer?.duration) {
      if (this.isRandom) {
        this.playRandom();
      } else if (this.playMode == LoopMode.LIST_LOOP) {
        this.playNext()
      } else {
        this.avPlayer.seek(this.avPlayer?.duration);
      }
      return;
    }

    let seekMode = this.getCurrentTime() < ms ? 0 : 1;
    if (this.isClipping) {
      ms = this.songItem!.getStartUs() / 1000 + ms;
    }
    let realTime = ms <= 0 ? 0 : ms;
    if (index || index == 0 && this.musicIndex != index) {
      this.avPlayer?.reset();
      this.loadAssent(index);
    } else {
      if ((this.state == AudioPlayerState.PREPARED || this.state == AudioPlayerState.PLAY ||
        this.state == AudioPlayerState.COMPLETED || this.state == AudioPlayerState.PAUSE) && this.avPlayer) {
        this.seekModule = SeekMode.SEEK;
        this.avPlayer.seek(realTime, seekMode);
      }
    }
  }

  private async loadUri(avPlayer: media.AVPlayer, uri: string) {
    if (uri?.startsWith('http')) {
      let headers: Record<string, string> = { "User-Agent": "User-Agent-Value" };
      if (this.songItem?.getHeader()) {
        headers = this.songItem?.getHeader() as Record<string, string>
      }
      let mediaSource: media.MediaSource = media.createMediaSourceWithUrl(uri, headers);
      avPlayer.setMediaSource(mediaSource, this.playStrategy);
    } else if (uri?.startsWith('file')) {
      if (this.context) {
        const dartFilePrefix = 'file:///';
        if (uri.startsWith(dartFilePrefix)) {
          uri = uri.slice(dartFilePrefix.length);
        }
        let fd: number = fileIo.openSync(uri).fd;
        let fileSize: number = fileIo.statSync(uri).size;
        let src: media.AVDataSrcDescriptor = {
          fileSize: fileSize,
          callback: (buf: ArrayBuffer, length: number, pos: number | undefined) => {
            let num = 0;
            if (buf == undefined || length == undefined || pos == undefined) {
              return -1;
            }
            num = fileIo.readSync(fd, buf, { offset: pos, length: length });
            if (num > 0 && (fileSize >= pos)) {
              return num;
            }
            return -1;
          }
        }
        src.fileSize = fileSize;
        avPlayer.dataSrc = src;
        if (this.avMetadataExtractor) {
          this.avMetadataExtractor.dataSrc = src;
        }
      }
    } else {
      if (this.context) {
        let fileDescriptor = await getContext(this).resourceManager.getRawFd(avPlayer.url)
          .catch((error: BusinessError) => {
            console.error(`resourceManager error code ${error.code} message ${error.message}`);
          });
        if (fileDescriptor) {
          let avFileDescriptor: media.AVFileDescriptor =
            { fd: fileDescriptor.fd, offset: fileDescriptor.offset, length: fileDescriptor.length };
          if (this.avMetadataExtractor) {
            this.avMetadataExtractor.fdSrc = avFileDescriptor;
          }
          avPlayer.fdSrc = avFileDescriptor;
        }
      }
    }
  }

  public addPublicMediaSources(index: number, mediaSources: Array<MediaSource>) {
    mediaSources.forEach((mediaSource: MediaSource) => {
      this.songList.push(mediaSource);
    });
    if (this.songList.length == 1 && this.avPlayer?.state == 'idle') {
      this.isFirst = true;
      this.loadAssent(0)
    }
  }

  public async removeMediaSourceRange(startIndex: number, endIndex: number) {
    this.songList.splice(startIndex, 1);
    if (this.songList.length > 0) {
      if (startIndex == this.songList.length) {
        this.loadAssent(this.songList.length - 1);
      } else if (startIndex == this.musicIndex) {
        this.loadAssent(this.musicIndex);
      }
    }
    this.updateCurrentIndex();
  }

  public moveMediaSource(currentIndex: number, newIndex: number) {
    let moveItem = this.songList.splice(currentIndex, 1);
    this.songList.splice(newIndex, 0, moveItem[0]);
    this.updateCurrentIndex();
  }

  private updateCurrentIndex() {
    let index = this.songList.indexOf(this.songItem!);
    if (index != -1) {
      this.musicIndex = index;
      this.mediaAvPlayerStateChangeListener?.onUpdateCurrentIndex(index);
    }
  }

  public setShuffleOrder(shuffleOrder: number[]) {
    this.shuffleOrder = shuffleOrder;
  }

  public async load(mediaSource: MediaSource, currentIndex: number, seekPostion: number = 0) {
    await this.initialization;
    if (this.isDisposed || this.avPlayer == null) {
      return;
    }
    this.completePendingPlay();
    this.speedAppliedForCurrentSource = false;
    this.isPrepared = false;
    this.initialPos = seekPostion ?? -1;
    if (this.initialPos != -1) {
      this.initialIndex = currentIndex
    }
    let mSource: media.MediaSource;
    let mediaType = mediaSource.getType();
    if (mediaType == "concatenating") {
      this.songList = mediaSource.getChildMediaSource();
      this.playMode = mediaSource.getMusicPlayMode();
      this.setShuffleOrder(mediaSource.shuffleOrder);
      this.loadAssent(currentIndex);
    } else {
      this.songList = [mediaSource];
      if (mediaType == "clipping") {
        this.loadAssent(currentIndex);
      } else if (mediaSource.getHeader()) {
        mSource = media.createMediaSourceWithUrl(mediaSource.getUri(), mediaSource.getHeader());
        await this.avPlayer?.setMediaSource(mSource, this.playStrategy);
        await this.avPlayer?.prepare();
      } else {
        this.loadAssent(currentIndex)
      }
    }
  }

  public async stop(): Promise<void> {
    const player = this.avPlayer;
    if (player == null || player.state == 'idle' || player.state == 'stopped' || player.state == 'released') {
      this.completePendingPlay();
      return;
    }
    try {
      await player.stop();
    } catch (err) {
      // A reset/release may already have moved AVPlayer out of the stoppable states.
      console.info(TAG, `AVPlayer stop ignored: ${JSON.stringify(err)}`);
    }
    if (this.avPlayer === player) {
      this.completePendingPlay();
    }
  }

  private start(seekMs?: number) {
    if (this.avPlayer) {
      this.avPlayer.prepare().then(() => {
      }).catch((error: BusinessError) => {
        console.error(TAG, `start error ${JSON.stringify(error)}`);
        this.state = AudioPlayerState.ERROR;
        this.updateIsPlay(false);
        this.isPrepared = false;
      });
    }
  }

  private updateIsPlay(display: boolean) {
    this.setPlayState({
      state: display ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position: {
        elapsedTime: this.getCurrentTime(),
        updateTime: new Date().getTime()
      }
    });
  }

  public getCurrentTime() {
    if (this.isPrepared && this.avPlayer) {
      if (this.isClipping) {
        return this.avPlayer.currentTime - (this.songItem!.getStartUs() / 1000);
      }
      return this.avPlayer.currentTime;
    }
    return 0;
  }

  private setPlayState(playbackState: avSession.AVPlaybackState) {
    if (this.session) {
      this.session.setAVPlaybackState(playbackState, (err: BusinessError) => {
        if (err) {
          console.error(TAG, `SetAVPlaybackState BusinessError: code: ${err.code}, message: ${err.message}`);
        } else {
          console.info(TAG, 'SetAVPlaybackState successfully');
        }
      });
    }
  }
}
