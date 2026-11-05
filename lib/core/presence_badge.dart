import 'package:flutter/material.dart';

import '../services/clinic_service.dart';
import 'format.dart';

/// "In clinic today" / "Not in today" for a doctor.
class PresenceBadge extends StatelessWidget {
  final bool present;
  const PresenceBadge({super.key, required this.present});

  @override
  Widget build(BuildContext context) {
    final color = present ? Colors.green : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 5),
          Text(
            present ? 'In clinic today' : 'Not in today',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: present ? Colors.green.shade800 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The same badge, kept up to date for one doctor (by the doctor's id).
class DoctorPresenceLive extends StatelessWidget {
  final String doctorId;
  const DoctorPresenceLive({super.key, required this.doctorId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: ClinicService().doctorPresentOnStream(doctorId),
      builder: (context, snap) {
        // No answer yet (or no permission): show nothing rather than "out".
        // A null value after that simply means "not marked in".
        if (snap.connectionState == ConnectionState.waiting || snap.hasError) {
          return const SizedBox.shrink();
        }
        return PresenceBadge(present: isPresentToday(snap.data));
      },
    );
  }
}
