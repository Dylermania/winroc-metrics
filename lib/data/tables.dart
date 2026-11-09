import 'package:drift/drift.dart';

import '../core/constants.dart';

mixin AuditColumns on Table {
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();
}

class Users extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get memberId => text().nullable().references(Members, #id)();
  TextColumn get displayName => text()();
  TextColumn get role => textEnum<ClubRole>()();
  TextColumn get pinHash => text()();
  TextColumn get pinSalt => text()();
  BoolColumn get biometricEnabled => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get lastLoginAt => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

class ActivityLogs extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get action => text()();
  TextColumn get targetTable => text().named('table_name')();
  TextColumn get recordId => text()();
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();
  TextColumn get deviceId => text()();
  TextColumn get createdAt => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class AcademicYears extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text()();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class Terms extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get academicYearId => text().references(AcademicYears, #id)();
  IntColumn get number => integer()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text()();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class CalendarPeriods extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get termId => text().references(Terms, #id)();
  TextColumn get kind => textEnum<CalendarKind>()();
  TextColumn get label => text()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Members extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get studentId => text().unique()();
  TextColumn get fullName => text()();
  IntColumn get form => integer()();
  TextColumn get house => text().nullable()();
  TextColumn get gender => text().nullable()();
  TextColumn get birthday => text().nullable()();
  TextColumn get guardianName => text().nullable()();
  TextColumn get guardianContact => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get joinDate => text()();
  TextColumn get clubRole => textEnum<ClubRole>().withDefault(const Constant('member'))();
  TextColumn get status => textEnum<MemberStatus>().withDefault(const Constant('active'))();
  TextColumn get qrToken => text().unique()();
  TextColumn get notes => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Teams extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get description => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class MemberTeams extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get memberId => text().references(Members, #id)();
  TextColumn get teamId => text().references(Teams, #id)();
  TextColumn get joinedAt => text()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {memberId, teamId}
      ];
}

class MemberFormHistories extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get memberId => text().references(Members, #id)();
  TextColumn get academicYearId => text().references(AcademicYears, #id)();
  IntColumn get form => integer()();
  TextColumn get statusThatYear => textEnum<MemberStatus>()();
  @override
  Set<Column> get primaryKey => {id};
}

class Skills extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  @override
  Set<Column> get primaryKey => {id};
}

class MemberSkills extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get memberId => text().references(Members, #id)();
  TextColumn get skillId => text().references(Skills, #id)();
  IntColumn get level => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {memberId, skillId}
      ];
}

class Sessions extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get termId => text().references(Terms, #id)();
  TextColumn get type => textEnum<SessionType>()();
  TextColumn get title => text()();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get date => text()();
  TextColumn get startTime => text()();
  TextColumn get endTime => text().nullable()();
  IntColumn get graceMinutes => integer().nullable()();
  TextColumn get state => textEnum<SessionState>().withDefault(const Constant('scheduled'))();
  TextColumn get checkinMode => textEnum<CheckinMode>().withDefault(const Constant('manual'))();
  TextColumn get selfCodeSecret => text()();
  TextColumn get createdBy => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class AttendanceRecords extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get memberId => text().references(Members, #id)();
  TextColumn get status => textEnum<AttendanceStatus>()();
  TextColumn get checkInAt => text().nullable()();
  TextColumn get method => textEnum<CheckinMethod>()();
  TextColumn get markedBy => text()();
  BoolColumn get verified => boolean().withDefault(const Constant(true))();
  TextColumn get selfToken => text().nullable()();
  IntColumn get selfBucket => integer().nullable()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {sessionId, memberId}
      ];
}

class AttendanceEdits extends Table {
  TextColumn get id => text()();
  TextColumn get attendanceRecordId => text().references(AttendanceRecords, #id)();
  TextColumn get oldStatus => textEnum<AttendanceStatus>()();
  TextColumn get newStatus => textEnum<AttendanceStatus>()();
  TextColumn get oldCheckInAt => text().nullable()();
  TextColumn get newCheckInAt => text().nullable()();
  TextColumn get reason => text()();
  TextColumn get editedBy => text()();
  TextColumn get editedAt => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Excuses extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get memberId => text().references(Members, #id)();
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get reason => text()();
  TextColumn get status => textEnum<ExcuseStatus>().withDefault(const Constant('pending'))();
  TextColumn get submittedAt => text()();
  TextColumn get reviewedBy => text().nullable()();
  TextColumn get reviewedAt => text().nullable()();
  TextColumn get reviewNote => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Levies extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get amountPesewas => integer()();
  TextColumn get frequency => textEnum<LevyFrequency>()();
  TextColumn get termId => text().nullable().references(Terms, #id)();
  TextColumn get appliesTo => text().withDefault(const Constant('all'))();
  TextColumn get teamId => text().nullable().references(Teams, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdBy => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class MemberDues extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get levyId => text().nullable().references(Levies, #id)();
  TextColumn get memberId => text().references(Members, #id)();
  IntColumn get amountPesewas => integer()();
  IntColumn get waiverPesewas => integer().withDefault(const Constant(0))();
  TextColumn get waiverReason => text().nullable()();
  TextColumn get waivedBy => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('levy'))();
  TextColumn get sourceId => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Payments extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get memberId => text().references(Members, #id)();
  TextColumn get receiptNo => text().unique()();
  IntColumn get amountPesewas => integer()();
  TextColumn get method => textEnum<PaymentMethod>()();
  TextColumn get transactionRef => text().nullable()();
  TextColumn get termId => text().references(Terms, #id)();
  TextColumn get receivedBy => text()();
  TextColumn get paidAt => text()();
  TextColumn get notes => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class PaymentAllocations extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get paymentId => text().references(Payments, #id)();
  TextColumn get memberDueId => text().references(MemberDues, #id)();
  IntColumn get amountPesewas => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class Fines extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get memberId => text().references(Members, #id)();
  TextColumn get category => text()();
  TextColumn get reason => text()();
  IntColumn get amountPesewas => integer()();
  TextColumn get sessionId => text().nullable().references(Sessions, #id)();
  BoolColumn get autoApplied => boolean().withDefault(const Constant(false))();
  TextColumn get status => textEnum<FineStatus>().withDefault(const Constant('open'))();
  TextColumn get createdBy => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<CategoryKind>()();
  TextColumn get name => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class Expenses extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get description => text()();
  IntColumn get amountPesewas => integer()();
  TextColumn get spentAt => text()();
  TextColumn get receiptPhotoPath => text().nullable()();
  TextColumn get recordedBy => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Projects extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => textEnum<ProjectStatus>().withDefault(const Constant('planning'))();
  TextColumn get startDate => text().nullable()();
  TextColumn get endDate => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class ProjectMembers extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get memberId => text().references(Members, #id)();
  TextColumn get role => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {projectId, memberId}
      ];
}

class ProjectHours extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get memberId => text().references(Members, #id)();
  TextColumn get workDate => text()();
  RealColumn get hours => real()();
  TextColumn get note => text().nullable()();
  TextColumn get loggedBy => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class InventoryItems extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text().nullable()();
  IntColumn get totalQty => integer()();
  IntColumn get lowStockThreshold => integer().withDefault(const Constant(2))();
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class InventoryLoans extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get itemId => text().references(InventoryItems, #id)();
  TextColumn get memberId => text().references(Members, #id)();
  IntColumn get qty => integer()();
  TextColumn get checkedOutAt => text()();
  TextColumn get dueDate => text().nullable()();
  TextColumn get checkedInAt => text().nullable()();
  TextColumn get conditionOut => text().nullable()();
  TextColumn get conditionIn => text().nullable()();
  TextColumn get handledBy => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Events extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get date => text()();
  TextColumn get location => text().nullable()();
  IntColumn get feePesewas => integer().withDefault(const Constant(0))();
  TextColumn get result => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get sessionId => text().nullable().references(Sessions, #id)();
  @override
  Set<Column> get primaryKey => {id};
}

class EventAttendees extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get eventId => text().references(Events, #id)();
  TextColumn get memberId => text().references(Members, #id)();
  TextColumn get role => text().nullable()();
  TextColumn get individualResult => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
        {eventId, memberId}
      ];
}

class Badges extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get criteriaKey => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class MemberBadges extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get memberId => text().references(Members, #id)();
  TextColumn get badgeId => text().references(Badges, #id)();
  TextColumn get awardedAt => text()();
  TextColumn get awardedBy => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class SessionResources extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get kind => textEnum<ResourceKind>()();
  TextColumn get title => text()();
  TextColumn get contentOrPath => text()();
  TextColumn get addedBy => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Announcements extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  TextColumn get createdBy => text()();
  TextColumn get expiresAt => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class MessageTemplates extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<TemplateKind>()();
  TextColumn get body => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Devices extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get platform => text()();
  TextColumn get lastSeenAt => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class ChangeLogs extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();
  TextColumn get targetTable => text().named('table_name')();
  TextColumn get recordId => text()();
  TextColumn get op => textEnum<SyncOp>()();
  TextColumn get payloadJson => text().nullable()();
  TextColumn get changedAt => text()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class SyncPeers extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get peerDeviceId => text().unique()();
  TextColumn get peerName => text()();
  TextColumn get address => text()();
  IntColumn get lastSentCursor => integer().withDefault(const Constant(0))();
  IntColumn get lastReceivedCursor => integer().withDefault(const Constant(0))();
  TextColumn get lastSyncAt => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class SyncConflicts extends Table with AuditColumns {
  TextColumn get id => text()();
  TextColumn get targetTable => text().named('table_name')();
  TextColumn get recordId => text()();
  TextColumn get localJson => text()();
  TextColumn get remoteJson => text()();
  TextColumn get resolution =>
      textEnum<ConflictResolution>().withDefault(const Constant('pending'))();
  TextColumn get resolvedBy => text().nullable()();
  TextColumn get resolvedAt => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Backups extends Table {
  TextColumn get id => text()();
  TextColumn get filePath => text()();
  TextColumn get kind => textEnum<BackupKind>()();
  TextColumn get createdAt => text()();
  IntColumn get sizeBytes => integer()();
  @override
  Set<Column> get primaryKey => {id};
}