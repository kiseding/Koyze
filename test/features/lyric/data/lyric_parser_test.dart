import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/lyric/data/lyric_parser.dart';

void main() {
  test('parseLrc plain lines without word timing', () {
    const raw = '''
[00:12.00]第一行
[00:15.50]第二行
''';
    final lyrics = LyricParser.parseLrc(raw);
    expect(lyrics.lines.length, 2);
    expect(lyrics.lines[0].text, '第一行');
    expect(lyrics.lines[0].hasWordTiming, isFalse);
    expect(lyrics.lines[0].time, const Duration(seconds: 12));
  });

  test('parseLrc LRCX relative word tags', () {
    const raw = r'''
[00:10.00]<0,200>七<200,200>里<400,300>香
[00:15.00]下一行
''';
    final lyrics = LyricParser.parseLrc(raw);
    expect(lyrics.lines.length, 2);
    final line = lyrics.lines.first;
    expect(line.text, '七里香');
    expect(line.hasWordTiming, isTrue);
    expect(line.words!.length, 3);
    expect(line.words![0].text, '七');
    expect(line.words![0].time, const Duration(seconds: 10));
    expect(line.words![0].duration, const Duration(milliseconds: 200));
    expect(line.words![1].time, const Duration(milliseconds: 10200));
    expect(line.words![2].text, '香');
  });

  test('parseLrc supports Kuwo millisecond row markers', () {
    const raw = r'''
[12340]<0,180>逐<180,220>字
[15000]下一句
''';
    final lyrics = LyricParser.parseLrc(raw);
    expect(lyrics.lines.length, 2);
    expect(lyrics.lines.first.time, const Duration(milliseconds: 12340));
    expect(lyrics.lines.first.text, '逐字');
    expect(lyrics.lines.first.hasWordTiming, isTrue);
  });

  test('parseLrc converts Kuwo encoded word timing using its scale tag', () {
    const raw = r'''
[kuwo:13]
[00:10.000]<1000,200>你<1800,200>好
[00:12.000]普通兜底
''';
    final lyrics = LyricParser.parseLrc(raw);
    expect(lyrics.lines[0].time, const Duration(milliseconds: 10000));
    expect(lyrics.lines[0].text, '你好');
    expect(lyrics.lines[0].hasWordTiming, isTrue);
    expect(lyrics.lines[0].words![0].time, const Duration(milliseconds: 10600));
    expect(
      lyrics.lines[0].words![0].duration,
      const Duration(milliseconds: 400),
    );
    expect(lyrics.lines[0].words![1].time, const Duration(milliseconds: 11000));
    expect(
      lyrics.lines[0].words![1].duration,
      const Duration(milliseconds: 800),
    );
    expect(lyrics.lines[1].text, '普通兜底');
    expect(lyrics.lines[1].hasWordTiming, isFalse);
  });

  test('invalid Kuwo timing scale falls back to plain line lyrics', () {
    const raw = r'''
[kuwo:invalid]
[00:10.000]<1000,200>普<1800,200>通
''';
    final lyrics = LyricParser.parseLrc(raw);
    expect(lyrics.lines.single.text, '普通');
    expect(lyrics.lines.single.hasWordTiming, isFalse);
    expect(lyrics.lines.single.time, const Duration(seconds: 10));
  });

  test('Kuwo final word cannot run beyond the next lyric line', () {
    const raw = r'''
[kuwo:13]
[00:10.000]<1000,200>前<1800,-800>句
[00:11.500]<0,0>后
''';
    final lyrics = LyricParser.parseLrc(raw);
    final last = lyrics.lines.first.words!.last;
    expect(last.time + last.duration!, lyrics.lines[1].time);
  });

  test('parseLrc yrc style word-before-tag', () {
    const raw = r'''
[00:05.00]你<0,180>好<180,220>吗
''';
    final lyrics = LyricParser.parseLrc(raw);
    expect(lyrics.lines.length, 1);
    final words = lyrics.lines.first.words!;
    expect(words.map((w) => w.text).join(), '你好吗');
    expect(words[0].duration, const Duration(milliseconds: 180));
    expect(words[1].time, const Duration(milliseconds: 5180));
  });

  test('parseQrc clock word tags', () {
    const raw = r'''
[00:12.34]<00:12.34>逐<00:12.50>字<00:12.70>歌
''';
    final lyrics = LyricParser.parseQrc(raw);
    expect(lyrics.lines.length, 1);
    final words = lyrics.lines.first.words!;
    expect(words.map((w) => w.text).join(), '逐字歌');
    expect(
      words[0].time,
      const Duration(minutes: 0, seconds: 12, milliseconds: 340),
    );
    expect(
      words[1].time,
      const Duration(minutes: 0, seconds: 12, milliseconds: 500),
    );
  });

  test('word fill progress for KTV', () {
    const raw = r'''
[00:10.00]<0,1000>A<1000,1000>B
''';
    final lyrics = LyricParser.parseLrc(raw);
    final line = lyrics.lines.first;
    expect(
      lyrics.getCurrentWordIndex(
        const Duration(seconds: 10, milliseconds: 500),
        0,
      ),
      0,
    );
    expect(
      lyrics.getWordFillProgress(
        const Duration(seconds: 10, milliseconds: 500),
        0,
        0,
      ),
      closeTo(0.5, 0.01),
    );
    expect(
      lyrics.getCurrentWordIndex(
        const Duration(seconds: 11, milliseconds: 200),
        0,
      ),
      1,
    );
    expect(line.words![1].text, 'B');
  });

  test('hasWordTiming detection', () {
    expect(LyricParser.hasWordTiming('[00:01.00]plain'), isFalse);
    expect(LyricParser.hasWordTiming(r'[00:01.00]<0,100>a'), isTrue);
    expect(LyricParser.hasWordTiming(r'<00:01.00>a'), isTrue);
  });

  test('parseQrc Tencent word tags with XML wrapper', () {
    const raw =
        r'''<?xml version="1.0"?><QrcInfos><LyricInfo LyricContent="[0,5890]A(0,368)B(368,368)C(736,368)D(1104,368)"/>''';
    final lyrics = LyricParser.parseQrc(raw);
    expect(lyrics.lines.length, 1);
    final line = lyrics.lines.first;
    expect(line.time, Duration.zero);
    expect(line.text, 'ABCD');
    expect(line.hasWordTiming, isTrue);
    expect(line.words!.length, 4);
    expect(line.words![1].time, const Duration(milliseconds: 368));
    expect(line.words![1].duration, const Duration(milliseconds: 368));
  });

  test('parseQrc Tencent raw timed lines', () {
    // 腾讯 QRC 的字 start 是绝对毫秒（从歌曲开始），与行时间一致。
    const raw = r'''[0,2250]A(0,368)B(368,368)
[2250,4500]C(2250,400)D(2650,300)''';
    final lyrics = LyricParser.parseQrc(raw);
    expect(lyrics.lines.length, 2);
    expect(lyrics.lines[0].text, 'AB');
    expect(lyrics.lines[0].hasWordTiming, isTrue);
    expect(lyrics.lines[1].time, const Duration(milliseconds: 2250));
    expect(lyrics.lines[1].words![0].time, const Duration(milliseconds: 2250));
    expect(lyrics.lines[1].words![1].time, const Duration(milliseconds: 2650));
  });

  test('hasWordTiming detects Tencent word tags', () {
    expect(LyricParser.hasWordTiming('[0,5890]A(0,368)B(368,368)'), isTrue);
    expect(LyricParser.hasWordTiming('[00:12.00]plain'), isFalse);
  });

  test('does not treat a single Kuwo parenthesized value as word timing', () {
    const raw = '[12340]普通歌词 (制作人: 123,456)';
    expect(LyricParser.hasWordTiming(raw), isFalse);
    final lyrics = LyricParser.parseLrc(raw);
    expect(lyrics.lines.single.text, '普通歌词 (制作人: 123,456)');
    expect(lyrics.lines.single.hasWordTiming, isFalse);
  });

  test('parseQrc real Tencent XML with metadata and punctuation', () {
    const raw = r'''<?xml version="1.0" encoding="utf-8"?>
<QrcInfos>
<QrcHeadInfo SaveTime="215" Version="100"/>
<LyricInfo LyricCount="1">
<Lyric_1 LyricType="1" LyricContent="[ti:Test Song]
[ar:Artist]
[offset:0]
[0,5890]AB(0,368)C(368,368)D(736,368)
[5890,5900]EF(5890,1180)G(7070,1180)
"/>''';
    final lyrics = LyricParser.parseQrc(raw);
    expect(lyrics.lines.length, 2);
    expect(lyrics.lines[0].text, 'ABCD');
    expect(lyrics.lines[0].hasWordTiming, isTrue);
    expect(lyrics.lines[0].words![1].time, const Duration(milliseconds: 368));
    expect(lyrics.lines[1].words![1].time, const Duration(milliseconds: 7070));
    expect(lyrics.lines[1].words![1].text, 'G');
  });

  group('同时间戳多行', () {
    test('两行连写时第二行作为翻译，不再多出一句重复歌词', () {
      final lyrics = LyricParser.parseLrc('''
[00:15.03]悴んだ心
[00:15.03]憔悴的心
''');

      expect(lyrics.lines, hasLength(1));
      expect(lyrics.lines.single.text, '悴んだ心');
      expect(lyrics.lines.single.translation, '憔悴的心');
    });

    test('三行连写时第三行另起一行，不被吞掉', () {
      final lyrics = LyricParser.parseLrc('''
[00:15.03]悴んだ心
[00:15.03]憔悴的心
[00:15.03]shi zu n da ko ko ro
''');

      expect(lyrics.lines, hasLength(2));
      expect(lyrics.lines.first.translation, '憔悴的心');
      expect(lyrics.lines.last.text, 'shi zu n da ko ko ro');
      expect(lyrics.lines.last.translation, isNull);
    });

    test('两行连写仍然只挂翻译', () {
      final lyrics = LyricParser.parseLrc('''
[00:15.03]沈むように
[00:15.03]像要沉下去一般
''');

      expect(lyrics.lines, hasLength(1));
      expect(lyrics.lines.single.translation, '像要沉下去一般');
    });
  });

  group('attachParallelText', () {
    test('按时间戳挂上翻译', () {
      final main = LyricParser.parseLrc('''
[00:12.00]沈むように
[00:16.00]溶けてゆく
''');
      final merged = LyricParser.attachParallelText(
        main,
        translation: '''
[00:12.00]像要沉下去一般
[00:16.00]渐渐融化
''',
      );

      expect(merged.lines[0].translation, '像要沉下去一般');
      expect(merged.lines[1].translation, '渐渐融化');
    });

    test('时间戳差 80ms 内仍按最近一行挂载', () {
      final main = LyricParser.parseLrc('[00:12.00]原文');
      final merged = LyricParser.attachParallelText(
        main,
        translation: '[00:12.06]译文',
      );
      expect(merged.lines.single.translation, '译文');
    });

    test('差得太远时宁可留空也不错行', () {
      final main = LyricParser.parseLrc('[00:12.00]原文');
      final merged = LyricParser.attachParallelText(
        main,
        translation: '[00:13.50]别的句子',
      );
      expect(merged.lines.single.translation, isNull);
    });

    test('没有附加文本时原样返回', () {
      final main = LyricParser.parseLrc('[00:12.00]原文');
      final merged = LyricParser.attachParallelText(main);
      expect(identical(merged, main), isTrue);
    });
  });
}
