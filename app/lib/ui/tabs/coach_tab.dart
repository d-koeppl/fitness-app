import 'package:flutter/material.dart';

import '../widgets/common.dart';

/// The coach chat arrives in phase 7 of the port. Until then the tab says
/// so, and the web app at fitness.koeppl.cc still has it.
class CoachTab extends StatelessWidget {
  const CoachTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const Notice('The coach is not in this app yet. Until it is, ask it in the web dashboard.');
  }
}
