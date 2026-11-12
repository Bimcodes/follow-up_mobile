import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/newcomer_record.dart';

class QuickActionsService {
  static String buildWelcomeMessage(NewcomerRecord record) {
    final firstName = record.fullName.trim().isNotEmpty
        ? record.fullName.trim().split(' ').last
        : 'there';
    return 'Hello $firstName! Welcome to Kingdom Life Chapel (OAU). '
        'We were truly blessed to have you worship with us, and we are praying along with you!';
  }

  static Future<bool> openWhatsApp(
    BuildContext context,
    NewcomerRecord record, {
    bool includeWelcomeText = true,
  }) async {
    final digits = record.digitsOnlyPhone;
    if (digits.isEmpty) {
      _showSnack(context, 'No phone number entered for ${record.fullName}.');
      return false;
    }

    final encodedMessage = includeWelcomeText
        ? Uri.encodeComponent(buildWelcomeMessage(record))
        : '';
    final waUri = Uri.parse(
      'https://wa.me/${record.whatsappPhone}${encodedMessage.isNotEmpty ? '?text=$encodedMessage' : ''}',
    );

    try {
      final launched = await launchUrl(
        waUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        _showSnack(context, 'Could not launch WhatsApp on this device.');
      }
      return launched;
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, 'Unable to open WhatsApp: $e');
      }
      return false;
    }
  }

  static Future<bool> makePhoneCall(
    BuildContext context,
    NewcomerRecord record,
  ) async {
    final digits = record.digitsOnlyPhone;
    if (digits.isEmpty) {
      _showSnack(context, 'No phone number entered for ${record.fullName}.');
      return false;
    }

    final telUri = Uri(scheme: 'tel', path: record.phoneNumber.trim());
    try {
      final launched = await launchUrl(telUri);
      if (!launched && context.mounted) {
        _showSnack(context, 'Could not open phone dialer.');
      }
      return launched;
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, 'Unable to place call: $e');
      }
      return false;
    }
  }

  static Future<bool> sendSms(
    BuildContext context,
    NewcomerRecord record,
  ) async {
    final digits = record.digitsOnlyPhone;
    if (digits.isEmpty) {
      _showSnack(context, 'No phone number entered for ${record.fullName}.');
      return false;
    }

    final smsUri = Uri(
      scheme: 'sms',
      path: record.phoneNumber.trim(),
      queryParameters: {'body': buildWelcomeMessage(record)},
    );
    try {
      final launched = await launchUrl(smsUri);
      if (!launched && context.mounted) {
        _showSnack(context, 'Could not open SMS app.');
      }
      return launched;
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, 'Unable to send SMS: $e');
      }
      return false;
    }
  }

  static Future<void> copyRecordToClipboard(
    BuildContext context,
    NewcomerRecord record,
  ) async {
    final summary = '''*KINGDOM LIFE CHAPEL (OAU) — NEWCOMER'S SLIP*
• *Name (Full):* ${record.fullName.isEmpty ? '-' : record.fullName}
• *Phone No (WhatsApp):* ${record.phoneNumber.isEmpty ? '-' : record.phoneNumber}
• *Department:* ${record.department.isEmpty ? '-' : record.department}
• *How were you invited:* ${record.invitedBy.isEmpty ? '-' : record.invitedBy}
• *Location/Address:* ${record.location.isEmpty ? '-' : record.location}
• *Prayer Points:* ${record.prayerPoints.isEmpty ? '-' : record.prayerPoints}
• *Status:* ${record.status.label}''';

    await Clipboard.setData(ClipboardData(text: summary));
    if (context.mounted) {
      _showSnack(
        context,
        'Copied ${record.fullName.isEmpty ? 'slip details' : record.fullName} to clipboard!',
      );
    }
  }

  static void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
