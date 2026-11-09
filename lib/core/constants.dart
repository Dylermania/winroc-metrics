import 'package:flutter/material.dart';

enum ClubRole { admin, president, secretary, treasurer, teamLead, member }

enum MemberStatus { active, probation, alumni, suspended }

enum SessionType { regular, workshop, competitionPrep, fieldTrip, specialEvent }

enum SessionState { scheduled, ongoing, closed }

enum CheckinMode { manual, qrScan, selfCode, mixed }

enum AttendanceStatus { present, late, excused, absent }

enum CheckinMethod { manual, qrScan, selfCode }

enum ExcuseStatus { pending, approved, rejected }

enum LevyFrequency { termly, monthly, oneOff }

enum PaymentMethod { cash, mtnMomo, telecelCash, airteltigoMoney, bank }

enum FineStatus { open, settled, waived }

enum CategoryKind { expense, sessionType, duesType, fine }

enum ProjectStatus { planning, active, completed }

enum CalendarKind { vacation, exam, holiday }

enum ResourceKind { note, file, link }

enum TemplateKind { duesReminder, guardianSummary, sessionReminder, custom }

enum SyncOp { insert, update, delete }

enum ConflictResolution { pending, local, remote }

enum BackupKind { manual, scheduled }

enum Capability { members, attendance, finance, admin, viewAll }

const Map<ClubRole, Set<Capability>> roleCapabilities = {
  ClubRole.admin: {
    Capability.members,
    Capability.attendance,
    Capability.finance,
    Capability.admin,
    Capability.viewAll,
  },
  ClubRole.president: {
    Capability.members,
    Capability.attendance,
    Capability.finance,
    Capability.viewAll,
  },
  ClubRole.secretary: {Capability.members, Capability.attendance, Capability.viewAll},
  ClubRole.treasurer: {Capability.finance, Capability.viewAll},
  ClubRole.teamLead: {Capability.attendance, Capability.viewAll},
  ClubRole.member: {},
};

extension ClubRoleX on ClubRole {
  String get label => switch (this) {
        ClubRole.admin => 'Patron',
        ClubRole.president => 'President',
        ClubRole.secretary => 'Secretary',
        ClubRole.treasurer => 'Treasurer',
        ClubRole.teamLead => 'Team Lead',
        ClubRole.member => 'Member',
      };

  bool can(Capability c) => roleCapabilities[this]!.contains(c);
}

extension MemberStatusX on MemberStatus {
  String get label => switch (this) {
        MemberStatus.active => 'Active',
        MemberStatus.probation => 'Probation',
        MemberStatus.alumni => 'Alumni',
        MemberStatus.suspended => 'Suspended',
      };

  Color get color => switch (this) {
        MemberStatus.active => const Color(0xFF2E7D32),
        MemberStatus.probation => const Color(0xFFF9A825),
        MemberStatus.alumni => const Color(0xFF607D8B),
        MemberStatus.suspended => const Color(0xFFC62828),
      };
}

extension SessionTypeX on SessionType {
  String get label => switch (this) {
        SessionType.regular => 'Regular Meeting',
        SessionType.workshop => 'Workshop',
        SessionType.competitionPrep => 'Competition Prep',
        SessionType.fieldTrip => 'Field Trip',
        SessionType.specialEvent => 'Special Event',
      };
}

extension AttendanceStatusX on AttendanceStatus {
  String get label => switch (this) {
        AttendanceStatus.present => 'Present',
        AttendanceStatus.late => 'Late',
        AttendanceStatus.excused => 'Excused',
        AttendanceStatus.absent => 'Absent',
      };

  Color get color => switch (this) {
        AttendanceStatus.present => const Color(0xFF2E7D32),
        AttendanceStatus.late => const Color(0xFFF9A825),
        AttendanceStatus.excused => const Color(0xFF1565C0),
        AttendanceStatus.absent => const Color(0xFFC62828),
      };

  bool get countsAsPresent =>
      this == AttendanceStatus.present || this == AttendanceStatus.late;
}

extension PaymentMethodX on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.mtnMomo => 'MTN MoMo',
        PaymentMethod.telecelCash => 'Telecel Cash',
        PaymentMethod.airteltigoMoney => 'AirtelTigo Money',
        PaymentMethod.bank => 'Bank',
      };
}

extension LevyFrequencyX on LevyFrequency {
  String get label => switch (this) {
        LevyFrequency.termly => 'Termly',
        LevyFrequency.monthly => 'Monthly',
        LevyFrequency.oneOff => 'One-off',
      };
}

extension ExcuseStatusX on ExcuseStatus {
  String get label => switch (this) {
        ExcuseStatus.pending => 'Pending',
        ExcuseStatus.approved => 'Approved',
        ExcuseStatus.rejected => 'Rejected',
      };
}

extension FineStatusX on FineStatus {
  String get label => switch (this) {
        FineStatus.open => 'Open',
        FineStatus.settled => 'Settled',
        FineStatus.waived => 'Waived',
      };
}

extension ProjectStatusX on ProjectStatus {
  String get label => switch (this) {
        ProjectStatus.planning => 'Planning',
        ProjectStatus.active => 'Active',
        ProjectStatus.completed => 'Completed',
      };
}

class Defaults {
  static const schoolName = 'Winneba Secondary School';
  static const clubName = 'Winroc Robotics Club';
  static const currency = 'GHS';
  static const graceMinutes = 15;
  static const attendanceThreshold = 75;
  static const autoLockMinutes = 5;
  static const lateFinePesewas = 0;
  static const syncPort = 8765;
  static const codeBucketSeconds = 30;
  static const maxBackups = 7;
}