import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../services/visit_service.dart';
import '../utils/date_utils.dart';
import '../widgets/member_avatar.dart';

/// Administrationssida för föräldrar att hantera besöksbokning.
class VisitAdminPage extends StatefulWidget {
  const VisitAdminPage({super.key});

  @override
  State<VisitAdminPage> createState() => _VisitAdminPageState();
}

class _VisitAdminPageState extends State<VisitAdminPage> {
  bool _loading = true;
  String? _errorMsg;
  String? _errorDetail;

  VisitLinkModel? _link;
  List<VisitBookingModel> _bookings = [];
  UserModel? _selectedPersonForNewLink;

  // Dagsläge för idag + 6 dagar framåt
  late List<DateTime> _weekDays;
  late DateTime _selectedDay;
  final Map<String, String> _dayStatuses = {};
  bool _updatingStatus = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _weekDays = List.generate(7, (i) => today.add(Duration(days: i)));
    _selectedDay = today;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
      _errorDetail = null;
    });

    try {
      final link = await VisitService.createOrGetVisitLink();
      List<VisitBookingModel> bookings = [];
      if (link != null) {
        bookings = await VisitService.listVisitBookings(
          linkId: link.linkId,
          fromDate: dateKey(_weekDays.first),
        );
      }

      if (mounted) {
        setState(() {
          _link = link;
          _bookings = bookings;
          _loading = false;
          _errorMsg = null;
          _errorDetail = null;
        });
      }
    } catch (e, stack) {
      developer.log('Kunde inte läsa in besöksdata', error: e, stackTrace: stack);
      if (mounted) {
        final errStr = e.toString();
        setState(() {
          _errorMsg = 'Kunde inte läsa in besöksdata.';
          _errorDetail = errStr.length > 120 ? errStr.substring(0, 120) : errStr;
          _loading = false;
        });
      }
    }
  }

  Future<void> _createLinkForSelectedPerson() async {
    if (_selectedPersonForNewLink == null) return;
    setState(() => _loading = true);
    try {
      final link = await VisitService.createOrGetVisitLink(
        personUid: _selectedPersonForNewLink!.uid,
      );
      if (link != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bokningslänk skapad för ${link.personName}! 🫶'),
            backgroundColor: const Color(0xFF6BAE75),
          ),
        );
      }
      await _loadData();
    } catch (e, stack) {
      developer.log('Kunde inte skapa bokningslänk', error: e, stackTrace: stack);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte skapa länken: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmRegenerateLink() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Skapa ny bokningslänk?'),
        content: const Text(
          'Den gamla länken slutar fungera omedelbart. Alla med gamla länken behöver få den nya.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Skapa ny'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      setState(() => _loading = true);
      try {
        final newLink = await VisitService.regenerateVisitLink(
          linkId: _link?.linkId,
          personUid: _link?.personUid,
        );
        if (mounted) {
          setState(() {
            _link = newLink;
            _loading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ny bokningslänk har skapats! 🫶'),
              backgroundColor: Color(0xFF6BAE75),
            ),
          );
        }
      } catch (e, stack) {
        developer.log('Kunde inte återskapa länk', error: e, stackTrace: stack);
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Kunde inte återskapa länken: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _copyLink() async {
    if (_link == null) return;
    await Clipboard.setData(ClipboardData(text: _link!.url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Länk kopierad till urklipp! 📋'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF6BAE75),
        ),
      );
    }
  }

  Future<void> _copyBookingManageLink(VisitBookingModel b) async {
    if (_link == null) return;
    final separator = _link!.url.contains('?') ? '&' : '?';
    final editUrl = '${_link!.url}${separator}b=${b.bookingId}&k=${b.editToken}';
    await Clipboard.setData(ClipboardData(text: editUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ändringslänk kopierad — skicka den till besökaren 📋'),
          duration: Duration(seconds: 3),
          backgroundColor: Color(0xFF6BAE75),
        ),
      );
    }
  }

  void _showShareDialog() {
    if (_link == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Dela bokningslänk 🫶'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Skicka denna länk till släkt och vänner som vill boka besök:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            SelectableText(
              _link!.url,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF2A6F97),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Stäng'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _copyLink();
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Kopiera länk'),
          ),
        ],
      ),
    );
  }

  Future<void> _setDayStatus(String status) async {
    if (_link == null || _updatingStatus) return;
    final dateStr = dateKey(_selectedDay);

    setState(() {
      _updatingStatus = true;
      _dayStatuses[dateStr] = status;
    });

    try {
      await VisitService.setVisitDayStatus(
        linkId: _link!.linkId,
        date: dateStr,
        status: status,
      );
      if (mounted) {
        setState(() => _updatingStatus = false);
      }
    } catch (e, stack) {
      developer.log('Kunde inte uppdatera dagstatus', error: e, stackTrace: stack);
      if (mounted) {
        setState(() => _updatingStatus = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte spara dagstatus: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmCancelBooking(VisitBookingModel booking) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Avboka besök?'),
        content: Text(
          'Vill du avboka besöket med ${booking.names} den ${booking.date} kl ${booking.time}?\n\n'
          'Kalenderhändelsen tas bort och dagen blir ledig igen för andra besökare.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Behåll'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Avboka'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        await VisitService.cancelVisitBookingAdmin(bookingId: booking.bookingId);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Besöket med ${booking.names} har avbokats. 🫶'),
              backgroundColor: const Color(0xFF6BAE75),
            ),
          );
        }
      } catch (e, stack) {
        developer.log('Kunde inte avboka besök', error: e, stackTrace: stack);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Kunde inte avboka besöket: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _callPhone(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$clean');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, stack) {
      developer.log('Kunde inte ringa $phone', error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunde inte ringa $phone')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final currentUser = provider.currentUser;
    final dayColor = AppTheme.getDayAccentColor();
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);

    // Endast föräldrar/admin
    if (currentUser != null && !currentUser.isParent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Column(
        children: [
          // Header
          Container(
            decoration: AppTheme.headerDecoration(),
            padding: AppTheme.paddingBelowStatusBar(context, bottom: 12),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_ios_rounded, color: textColor),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    'Besöksbokning 🫶',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh_rounded, color: textColor),
                  tooltip: 'Uppdatera',
                  onPressed: _loadData,
                ),
              ],
            ),
          ),

          // Innehåll
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: dayColor),
                  )
                : _errorMsg != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  size: 48, color: Colors.red.shade300),
                              const SizedBox(height: 12),
                              Text(_errorMsg!,
                                  style: const TextStyle(fontSize: 16)),
                              if (_errorDetail != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _errorDetail!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _loadData,
                                child: const Text('Försök igen'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: dayColor,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          children: [
                            // 1. Länkkort / Personväljare
                            _buildLinkCard(dayColor, provider.familyMembers),
                            if (_link != null) ...[
                              const SizedBox(height: 16),
                              // 2. Dagsläge
                              _buildDayStatusCard(dayColor),
                              const SizedBox(height: 16),
                              // 3. Kommande bokningar
                              _buildBookingsCard(dayColor),
                            ],
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkCard(Color dayColor, List<UserModel> members) {
    if (_link == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.cardDecoration(radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vem gäller besöken?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Välj vem i familjen som ska ta emot besök för att skapa bokningslänken:',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: members.map((m) {
                final isSel = _selectedPersonForNewLink?.uid == m.uid;
                final color = AppTheme.colorFromHex(m.color);
                return ChoiceChip(
                  avatar: FamilyMemberAvatar(member: m, size: 24),
                  label: Text(m.name),
                  selected: isSel,
                  selectedColor: color.withValues(alpha: 0.25),
                  onSelected: (_) => setState(() => _selectedPersonForNewLink = m),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _selectedPersonForNewLink == null
                    ? null
                    : _createLinkForSelectedPerson,
                icon: const Icon(Icons.link_rounded),
                label: const Text('Skapa bokningslänk 🫶'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: dayColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final personFirstName = _link!.personName.split(' ').first;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: dayColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.favorite_rounded, color: dayColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bokningslänk för $personFirstName',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Dela med släkt & vänner (max 1 sällskap/dag)',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Länkvisning
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _link!.url,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2A6F97),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: 'Kopiera',
                  onPressed: _copyLink,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Åtgärdsknappar
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyLink,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Kopiera'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showShareDialog,
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Dela'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.sync_rounded),
                tooltip: 'Skapa ny länk (invaliderar gamla)',
                onPressed: _confirmRegenerateLink,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayStatusCard(Color dayColor) {
    final selectedDateStr = dateKey(_selectedDay);
    final currentStatus = _dayStatuses[selectedDateStr] ?? 'green';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: dayColor, size: 20),
              const SizedBox(width: 8),
              Text('Dagsläge & ork', style: AppTheme.cardTitleStyle),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Styr om besök passar de närmaste dagarna. Rött spärrar alla tider.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),

          // Horisontell datumremsa
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _weekDays.map((d) {
                final dStr = dateKey(d);
                final isSel = d.year == _selectedDay.year &&
                    d.month == _selectedDay.month &&
                    d.day == _selectedDay.day;
                final status = _dayStatuses[dStr] ?? 'green';

                final isToday = d.difference(_weekDays.first).inDays == 0;
                final dayName = isToday
                    ? 'Idag'
                    : DateFormat('E', 'sv').format(d).toUpperCase();

                Color statusColor = const Color(0xFF6BAE75); // green
                if (status == 'yellow') {
                  statusColor = const Color(0xFFF39C12);
                } else if (status == 'red') {
                  statusColor = const Color(0xFFE74C3C);
                }

                return GestureDetector(
                  onTap: () => setState(() => _selectedDay = d),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSel
                          ? dayColor.withValues(alpha: 0.15)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSel ? dayColor : Colors.grey.shade200,
                        width: isSel ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          dayName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSel ? dayColor : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${d.day}/${d.month}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Statusknappar för vald dag
          Text(
            'Läge för ${DateFormat('EEEE d MMMM', 'sv').format(_selectedDay)}:',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatusButton(
                  label: '💚 Kom gärna',
                  statusKey: 'green',
                  isSelected: currentStatus == 'green',
                  activeColor: const Color(0xFF6BAE75),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatusButton(
                  label: '💛 Trött idag',
                  statusKey: 'yellow',
                  isSelected: currentStatus == 'yellow',
                  activeColor: const Color(0xFFF39C12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatusButton(
                  label: '❤️ Passar inte',
                  statusKey: 'red',
                  isSelected: currentStatus == 'red',
                  activeColor: const Color(0xFFE74C3C),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusButton({
    required String label,
    required String statusKey,
    required bool isSelected,
    required Color activeColor,
  }) {
    return Material(
      color: isSelected ? activeColor : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _setDayStatus(statusKey),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookingsCard(Color dayColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: dayColor, size: 20),
              const SizedBox(width: 8),
              Text('Kommande bokningar', style: AppTheme.cardTitleStyle),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: dayColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_bookings.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: dayColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_bookings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.event_available_rounded,
                        size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text(
                      'Inga kommande besök bokade än.',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final b in _bookings) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: dayColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_formatBookingDate(b.date)} · Ankomst ${b.time}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: dayColor,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (b.editToken.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.link_rounded,
                                size: 20, color: Colors.grey.shade700),
                            tooltip: 'Kopiera ändringslänk',
                            onPressed: () => _copyBookingManageLink(b),
                          ),
                        IconButton(
                          icon: Icon(Icons.cancel_outlined,
                              size: 20, color: Colors.red.shade400),
                          tooltip: 'Avboka besök',
                          onPressed: () => _confirmCancelBooking(b),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '🫶 ${b.names}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (b.phone.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () => _callPhone(b.phone),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone_rounded,
                                  size: 14, color: Colors.blue.shade700),
                              const SizedBox(width: 4),
                              Text(
                                b.phone,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue.shade700,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  String _formatBookingDate(String dateStr) {
    final d = parseDate(dateStr);
    if (d == null) return dateStr;
    try {
      return DateFormat('E d/M', 'sv').format(d);
    } catch (_) {
      return '${d.day}/${d.month}';
    }
  }
}
