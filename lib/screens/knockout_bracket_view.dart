import 'package:flutter/material.dart';
import '../data/api_client.dart';
import '../l10n/app_strings.dart';
import '../models/match_model.dart';
import '../models/tournament.dart';
import '../utils/zoom_route.dart';
import '../widgets/team_avatar.dart';
import 'match_detail_screen.dart';
import 'knockout_results_screen.dart';
import '../theme/app_theme.dart';

const double _kCardWidth = 220;
const double _kCardHeight = 96;
const double _kBaseGap = 20;
const double _kConnectorWidth = 40;
const double _kTitleHeight = 40;
// Approximate vertical position (from the top of a match card) of the
// team A row and team B row, based on the card's internal layout
// (status label + team A row + team B row, vertically centered).
const double _kCardTeamARowY = 45;
const double _kCardTeamBRowY = 73;

/// Computes the vertical center (in logical pixels) of every match in
/// every round. Round 0 is evenly spaced; every later round's card sits
/// at the exact vertical average of the two matches feeding into it —
/// this is what makes the elbow connector lines meet cleanly, the way
/// bracket pages on major tournament sites are built.
List<List<double>> _computeCenters(int round0Count) {
  final round0 = List<double>.generate(
      round0Count, (i) => i * (_kCardHeight + _kBaseGap) + _kCardHeight / 2);
  final all = <List<double>>[round0];
  var current = round0;
  while (current.length > 1) {
    final next = <double>[];
    for (int j = 0; j < current.length; j += 2) {
      next.add((current[j] + current[j + 1]) / 2);
    }
    all.add(next);
    current = next;
  }
  return all;
}

class KnockoutBracketView extends StatelessWidget {
  final Tournament tournament;
  const KnockoutBracketView({super.key, required this.tournament});

  String _roundLabel(BuildContext context, int round, int totalRounds) {
    final fromEnd = totalRounds - 1 - round;
    if (fromEnd == 0) return context.tr('final');
    if (fromEnd == 1) return context.tr('semiFinals');
    if (fromEnd == 2) return context.tr('quarterFinals');
    final teamsInRound = (1 << (fromEnd + 1));
    return '${context.tr('roundOf')} $teamsInRound';
  }

  @override
  Widget build(BuildContext context) {
    final mainMatches = tournament.matches.toList();
    if (mainMatches.isEmpty) {
      return Center(child: Text(context.tr('notPlayed')));
    }
    final totalRounds = mainMatches.map((m) => m.round).reduce((a, b) => a > b ? a : b) + 1;
    final isComplete = tournament.champion != null;

    final matchesByRound = <int, List<MatchModel>>{};
    for (int r = 0; r < totalRounds; r++) {
      matchesByRound[r] = mainMatches.where((m) => m.round == r).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
    }
    final round0Count = matchesByRound[0]!.length;
    final centers = _computeCenters(round0Count);
    final totalContentHeight =
        round0Count * _kCardHeight + (round0Count - 1) * _kBaseGap;
    final totalWidth =
        totalRounds * _kCardWidth + (totalRounds - 1) * _kConnectorWidth + 40;

    return Column(
      children: [
        if (isComplete)
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                  ZoomRoute(page: KnockoutResultsScreen(tournament: tournament))),
              icon: const Icon(Icons.emoji_events, color: Colors.amber),
              label: Text(context.tr('finalResults')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        Expanded(
          child: InteractiveViewer(
            minScale: 0.15,
            maxScale: 2.5,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(200),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: totalWidth,
                height: totalContentHeight + _kTitleHeight,
                child: Stack(
                  children: [
                    // Connector lines drawn first, underneath the cards.
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BracketConnectorPainter(
                          centers: centers,
                          matchesByRound: matchesByRound,
                          color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
                          highlightColor: const Color(0xFFD1FAE5),
                        ),
                      ),
                    ),
                    // Round titles.
                    for (int r = 0; r < totalRounds; r++)
                      Positioned(
                        left: r * (_kCardWidth + _kConnectorWidth),
                        top: 0,
                        width: _kCardWidth,
                        child: Text(
                          _roundLabel(context, r, totalRounds),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    // Match cards, absolutely positioned at their computed centers.
                    for (int r = 0; r < totalRounds; r++)
                      for (int i = 0; i < matchesByRound[r]!.length; i++)
                        Positioned(
                          left: r * (_kCardWidth + _kConnectorWidth),
                          top: _kTitleHeight + centers[r][i] - _kCardHeight / 2,
                          width: _kCardWidth,
                          height: _kCardHeight,
                          child: _MatchCard(
                            tournament: tournament,
                            match: matchesByRound[r]![i],
                          ),
                        ),
                    // Champion marker after the final.
                    if (isComplete)
                      Positioned(
                        left: totalRounds * (_kCardWidth + _kConnectorWidth) - _kConnectorWidth + 6,
                        top: _kTitleHeight + centers.last[0] - 14,
                        child: const Icon(Icons.emoji_events, color: Color(0xFFFFD86B), size: 28),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Draws the classic bracket "elbow" connectors: out from each of the two
/// matches in round r, joined by a vertical segment, then a single
/// horizontal line feeding into the next round's match.
///
/// As matches get decided, the relevant segments switch to a thicker,
/// brighter color so it's visually obvious which path a team advanced
/// through — a stub lights up as soon as its match is played, the
/// junction lights up once both feeder matches are played, and the exit
/// line lights up once the next round's match is itself decided too.
class _BracketConnectorPainter extends CustomPainter {
  final List<List<double>> centers;
  final Map<int, List<MatchModel>> matchesByRound;
  final Color color;
  final Color highlightColor;
  _BracketConnectorPainter({
    required this.centers,
    required this.matchesByRound,
    required this.color,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final highlightPaint = Paint()
      ..color = highlightColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int r = 0; r < centers.length - 1; r++) {
      final xStart = r * (_kCardWidth + _kConnectorWidth) + _kCardWidth;
      final xMid = xStart + _kConnectorWidth / 2;
      final xJog = xStart + _kConnectorWidth - 8; // short jog right before the next card
      final xEnd = xStart + _kConnectorWidth;
      final current = centers[r];
      final roundMatches = matchesByRound[r];
      final nextRoundMatches = matchesByRound[r + 1];

      for (int j = 0; j + 1 < current.length; j += 2) {
        final yTop = _kTitleHeight + current[j];
        final yBottom = _kTitleHeight + current[j + 1];

        final topMatch = roundMatches != null && j < roundMatches.length ? roundMatches[j] : null;
        final bottomMatch =
            roundMatches != null && j + 1 < roundMatches.length ? roundMatches[j + 1] : null;
        final destMatch = nextRoundMatches != null && (j ~/ 2) < nextRoundMatches.length
            ? nextRoundMatches[j ~/ 2]
            : null;
        final destCardTop =
            destMatch != null ? _kTitleHeight + centers[r + 1][j ~/ 2] - _kCardHeight / 2 : null;

        final topDecided = topMatch?.isPlayed ?? false;
        final bottomDecided = bottomMatch?.isPlayed ?? false;

        // Stubs out of each source match.
        canvas.drawLine(Offset(xStart, yTop), Offset(xMid, yTop),
            topDecided ? highlightPaint : basePaint);
        canvas.drawLine(Offset(xStart, yBottom), Offset(xMid, yBottom),
            bottomDecided ? highlightPaint : basePaint);
        // Junction connecting the two stubs.
        canvas.drawLine(Offset(xMid, yTop), Offset(xMid, yBottom),
            (topDecided && bottomDecided) ? highlightPaint : basePaint);

        if (destCardTop != null) {
          // Each line now travels all the way to the exact row (team A or
          // team B) inside the next round's card, not just its midpoint —
          // so it visually connects right up to where that team's name
          // will be written. The whole path lights up as soon as its
          // source match is decided (that's when the winner's name
          // actually appears in the next round's slot).
          final destTeamARowY = destCardTop + _kCardTeamARowY;
          final destTeamBRowY = destCardTop + _kCardTeamBRowY;
          final topPaint = topDecided ? highlightPaint : basePaint;
          final bottomPaint = bottomDecided ? highlightPaint : basePaint;

          canvas.drawLine(Offset(xMid, yTop), Offset(xJog, yTop), topPaint);
          canvas.drawLine(Offset(xJog, yTop), Offset(xJog, destTeamARowY), topPaint);
          canvas.drawLine(Offset(xJog, destTeamARowY), Offset(xEnd, destTeamARowY), topPaint);

          canvas.drawLine(Offset(xMid, yBottom), Offset(xJog, yBottom), bottomPaint);
          canvas.drawLine(Offset(xJog, yBottom), Offset(xJog, destTeamBRowY), bottomPaint);
          canvas.drawLine(Offset(xJog, destTeamBRowY), Offset(xEnd, destTeamBRowY), bottomPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BracketConnectorPainter oldDelegate) =>
      oldDelegate.centers != centers ||
      oldDelegate.color != color ||
      oldDelegate.matchesByRound != matchesByRound;
}

class _MatchCard extends StatelessWidget {
  final Tournament tournament;
  final MatchModel match;
  const _MatchCard({required this.tournament, required this.match});

  @override
  Widget build(BuildContext context) {
    final a = tournament.teamById(match.teamAId);
    final b = tournament.teamById(match.teamBId);
    final canOpen = a != null && b != null && !match.isBye;
    final twoLegged = tournament.isTwoLeggedMatch(match);

    String statusLabel;
    int? displayScoreA;
    int? displayScoreB;

    if (!twoLegged) {
      statusLabel = match.isPlayed ? context.tr('fullTime') : context.tr('notPlayed');
      displayScoreA = match.scoreA;
      displayScoreB = match.scoreB;
    } else if (match.scoreA == null) {
      statusLabel = context.tr('notPlayed');
      displayScoreA = null;
      displayScoreB = null;
    } else if (match.scoreA2 == null) {
      statusLabel = context.tr('leg1');
      displayScoreA = match.scoreA;
      displayScoreB = match.scoreB;
    } else if (match.isPlayed) {
      statusLabel = match.penA != null
          ? '${context.tr('fullTime')} (${context.tr('penalties')} ${match.penA}-${match.penB})'
          : context.tr('fullTime');
      displayScoreA = (match.scoreA ?? 0) + (match.scoreA2 ?? 0);
      displayScoreB = (match.scoreB ?? 0) + (match.scoreB2 ?? 0);
    } else {
      statusLabel = context.tr('penalties');
      displayScoreA = (match.scoreA ?? 0) + (match.scoreA2 ?? 0);
      displayScoreB = (match.scoreB ?? 0) + (match.scoreB2 ?? 0);
    }

    return Material(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: InkWell(
        onTap: canOpen && (match.isPlayed || ApiClient.instance.canEdit(tournament))
            ? () => Navigator.of(context).push(ZoomRoute(
                page: MatchDetailScreen(
                    tournament: tournament,
                    match: match,
                    isLeague: false,
                    readOnly: match.isPlayed)))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                statusLabel,
                style: TextStyle(fontSize: 10, color: mutedText(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              _TeamRow(
                team: a,
                score: displayScoreA,
                isWinner: match.winnerId != null && match.winnerId == a?.id,
                isLoser: match.isPlayed && match.winnerId != null && a != null && match.winnerId != a.id,
              ),
              const SizedBox(height: 6),
              _TeamRow(
                team: b,
                score: displayScoreB,
                isWinner: match.winnerId != null && match.winnerId == b?.id,
                isLoser: match.isPlayed && match.winnerId != null && b != null && match.winnerId != b.id,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  final dynamic team;
  final int? score;
  final bool isWinner;
  final bool isLoser;
  const _TeamRow({required this.team, required this.score, required this.isWinner, this.isLoser = false});

  @override
  Widget build(BuildContext context) {
    // Theme-aware muted color for eliminated teams — adapts automatically
    // so the name stays readable in both light and dark mode (a fixed
    // white was invisible against light mode's white cards).
    final loserColor = Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.5) ??
        mutedText(context);

    return Row(
      children: [
        if (team != null)
          TeamAvatar(name: team.name, imagePath: team.imagePath, radius: 11)
        else
          const CircleAvatar(radius: 11, backgroundColor: Colors.transparent, child: Icon(Icons.shield_outlined, size: 18, color: Colors.grey)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            team?.name ?? '—',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
              color: isWinner ? const Color(0xFF4ADE80) : (isLoser ? loserColor : null),
              decoration: isLoser ? TextDecoration.lineThrough : null,
              decorationColor: loserColor,
              decorationThickness: 1,
              shadows: isWinner
                  ? [Shadow(color: const Color(0xFF4ADE80).withValues(alpha: 0.65), blurRadius: 8)]
                  : null,
            ),
          ),
        ),
        if (score != null)
          Text('$score',
              style: TextStyle(
                  fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
                  color: isWinner ? const Color(0xFF4ADE80) : (isLoser ? loserColor : null))),
      ],
    );
  }
}
