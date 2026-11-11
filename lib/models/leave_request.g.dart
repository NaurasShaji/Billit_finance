// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'leave_request.dart';

class LeaveRequestAdapter extends TypeAdapter<LeaveRequest> {
  @override
  final int typeId = 17;

  @override
  LeaveRequest read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return LeaveRequest(
      id: fields[0] as String,
      employeeId: fields[1] as String,
      leaveType: fields[2] as String,
      startDate: fields[3] as DateTime,
      endDate: fields[4] as DateTime,
      reason: fields[5] as String? ?? '',
      status: fields[6] as String? ?? 'pending',
      reviewedBy: fields[7] as String? ?? '',
      reviewedAt: fields[8] as DateTime?,
      createdAt: fields[9] as DateTime? ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, LeaveRequest obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.employeeId)
      ..writeByte(2)
      ..write(obj.leaveType)
      ..writeByte(3)
      ..write(obj.startDate)
      ..writeByte(4)
      ..write(obj.endDate)
      ..writeByte(5)
      ..write(obj.reason)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.reviewedBy)
      ..writeByte(8)
      ..write(obj.reviewedAt)
      ..writeByte(9)
      ..write(obj.createdAt);
  }
}
