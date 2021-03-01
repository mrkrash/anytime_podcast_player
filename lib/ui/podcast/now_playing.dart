// Copyright 2020-2021 Ben Hills. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/entities/episode.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/services/audio/audio_player_service.dart';
import 'package:anytime/ui/podcast/chapter_selector.dart';
import 'package:anytime/ui/podcast/dot_decoration.dart';
import 'package:anytime/ui/podcast/playback_error_listener.dart';
import 'package:anytime/ui/podcast/player_position_controls.dart';
import 'package:anytime/ui/podcast/player_transport_controls.dart';
import 'package:anytime/ui/widgets/delayed_progress_indicator.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/style.dart';
import 'package:optimized_cached_image/optimized_cached_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// This is the full-screen player Widget which is invoked
/// by touching the mini player. This displays the podcast
/// image, episode notes and standard playback controls.
class NowPlaying extends StatefulWidget {
  @override
  _NowPlayingState createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlaying> with WidgetsBindingObserver {
  StreamSubscription<AudioState> playingStateSubscription;
  var textGroup = AutoSizeGroup();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    var popped = false;

    // If the episode finishes we can close.
    playingStateSubscription =
        audioBloc.playingState.where((state) => state == AudioState.stopped).listen((playingState) async {
      // Prevent responding to multiple stop events after we've popped and lost context.
      if (!popped) {
        Navigator.pop(context);
        popped = true;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    playingStateSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context);
    final playerBuilder = PlayerControlsBuilder.of(context);

    return StreamBuilder<Episode>(
        stream: audioBloc.nowPlaying,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Container();
          }

          var duration = snapshot.data == null ? 0 : snapshot.data.duration;
          final transportBuilder = playerBuilder?.builder(duration);

          return DefaultTabController(
              length: snapshot.data.hasChapters ? 3 : 2,
              initialIndex: snapshot.data.hasChapters ? 1 : 0,
              child: Scaffold(
                appBar: AppBar(
                  brightness: Theme.of(context).brightness,
                  backgroundColor: Colors.transparent,
                  elevation: 0.0,
                  leading: IconButton(
                    tooltip: L.of(context).minimise_player_window_button_label,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: Theme.of(context).primaryIconTheme.color,
                    ),
                    onPressed: () => {
                      Navigator.pop(context),
                    },
                  ),
                  flexibleSpace: PlaybackErrorListener(
                    child: snapshot.data.hasChapters
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              EpisodeTabBarWithChapters(),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              EpisodeTabBar(),
                            ],
                          ),
                  ),
                ),
                body: snapshot.data.hasChapters
                    ? EpisodeTabBarViewWithChapters(
                        episode: snapshot.data,
                      )
                    : EpisodeTabBarView(
                        episode: snapshot.data,
                      ),
                bottomNavigationBar: transportBuilder != null
                    ? transportBuilder(context)
                    : SizedBox(
                        height: 140.0,
                        child: NowPlayingTransport(),
                      ),
              ));
        });
  }
}

class EpisodeTabBar extends StatelessWidget {
  const EpisodeTabBar({
    Key key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TabBar(
      isScrollable: true,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: DotDecoration(colour: Theme.of(context).primaryColor),
      tabs: [
        Tab(
          child: Align(
            alignment: Alignment.center,
            child: Text(L.of(context).episode_label),
          ),
        ),
        Tab(
          child: Align(
            alignment: Alignment.center,
            child: Text(L.of(context).notes_label),
          ),
        ),
      ],
    );
  }
}

class EpisodeTabBarWithChapters extends StatelessWidget {
  const EpisodeTabBarWithChapters({
    Key key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TabBar(
      isScrollable: true,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: DotDecoration(colour: Theme.of(context).primaryColor),
      tabs: [
        Tab(
          child: Align(
            alignment: Alignment.center,
            child: Text(L.of(context).chapters_label),
          ),
        ),
        Tab(
          child: Align(
            alignment: Alignment.center,
            child: Text(L.of(context).episode_label),
          ),
        ),
        Tab(
          child: Align(
            alignment: Alignment.center,
            child: Text(L.of(context).notes_label),
          ),
        ),
      ],
    );
  }
}

class EpisodeTabBarView extends StatelessWidget {
  final Episode episode;
  final AutoSizeGroup textGroup;

  EpisodeTabBarView({
    Key key,
    this.episode,
    this.textGroup,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      children: [
        NowPlayingHeader(
          imageUrl: episode.imageUrl,
          title: episode.title,
          description: episode.description,
          textGroup: textGroup,
        ),
        NowPlayingDetails(title: episode.title, description: episode.description),
      ],
    );
  }
}

class EpisodeTabBarViewWithChapters extends StatelessWidget {
  final Episode episode;
  final AutoSizeGroup textGroup;

  EpisodeTabBarViewWithChapters({
    Key key,
    this.episode,
    this.textGroup,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context);

    return TabBarView(
      children: [
        ChapterSelector(
          episode: episode,
        ),
        StreamBuilder<PositionState>(
            stream: audioBloc.playPosition,
            builder: (context, snapshot) {
              final e = snapshot.hasData ? snapshot.data.episode : episode;
              return NowPlayingHeader(
                imageUrl: e.positionalImageUrl,
                title: e.title,
                description: e.description,
                subTitle: e.currentChapter == null ? '' : e.currentChapter.title,
                textGroup: textGroup,
              );
            }),
        NowPlayingDetails(title: episode.title, description: episode.description),
      ],
    );
  }
}

class NowPlayingHeader extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String description;
  final String subTitle;
  final AutoSizeGroup textGroup;

  const NowPlayingHeader({
    @required this.imageUrl,
    @required this.title,
    @required this.description,
    @required this.textGroup,
    this.subTitle,
  });

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context);

    return StreamBuilder<AudioState>(
        stream: audioBloc.playingState,
        builder: (context, statesnap) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Expanded(
                  flex: 7,
                  child: OptimizedCacheImage(
                    useScaleCacheManager: true,
                    width: 360,
                    height: 360,
                    imageUrl: imageUrl,
                    placeholder: (context, url) {
                      return DelayedCircularProgressIndicator();
                    },
                    errorWidget: (_, __, dynamic ___) {
                      return Container(
                        constraints: BoxConstraints.expand(),
                        child: Placeholder(
                          fallbackHeight: 360,
                          fallbackWidth: 360,
                          color: Colors.grey,
                          strokeWidth: 1,
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 16.0,
                      bottom: 0.0,
                      left: 16.0,
                      right: 16.0,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 2,
                          child: AutoSizeText(
                            title ?? '',
                            group: textGroup,
                            textAlign: TextAlign.center,
                            minFontSize: 12.0,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20.0,
                            ),
                            maxLines: 3,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0.0, 4.0, 0.0, 0.0),
                            child: AutoSizeText(
                              subTitle ?? '',
                              group: textGroup,
                              minFontSize: 10.0,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.normal,
                                fontSize: 16.0,
                              ),
                              maxLines: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        });
  }
}

class NowPlayingDetails extends StatelessWidget {
  final String title;
  final String description;

  const NowPlayingDetails({
    @required this.title,
    @required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Padding(
          padding: const EdgeInsets.only(
            top: 8.0,
            left: 16.0,
            right: 16.0,
          ),
          child: Html(
            data: description,
            style: {
              'html': Style(
                fontSize: FontSize.large,
              ),
            },
            onLinkTap: (url) {
              canLaunch(url).then((value) => launch(url));
            },
          ),
        ),
      ),
    );
  }
}

class NowPlayingTransport extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Divider(
          height: 0.0,
        ),
        PlayerPositionControls(),
        PlayerTransportControls(),
      ],
    );
  }
}

class PlayerControlsBuilder extends InheritedWidget {
  final WidgetBuilder Function(int duration) builder;

  PlayerControlsBuilder({
    Key key,
    @required this.builder,
    @required Widget child,
  })  : assert(builder != null),
        assert(child != null),
        super(key: key, child: child);

  static PlayerControlsBuilder of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PlayerControlsBuilder>();
  }

  @override
  bool updateShouldNotify(PlayerControlsBuilder oldWidget) {
    return builder != oldWidget.builder;
  }
}
