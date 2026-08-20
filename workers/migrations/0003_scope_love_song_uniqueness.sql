DROP INDEX IF EXISTS uniq_ps_love_song;

CREATE UNIQUE INDEX uniq_ps_love_song
  ON playlist_songs(playlist_id, user_id, songmid, source)
  WHERE playlist_id = 'love';
