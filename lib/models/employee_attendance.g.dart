// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employee_attendance.dart';

class EmployeeAttendanceAdapter extends TypeAdapter<EmployeeAttendance> {
  @override
  final int typeId = 16;

  @override
  EmployeeAttendance read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return EmployeeAttendance(
      id: fields[0] as String,
      employeeId: fields[1] as String,
      date: fields[2] as DateTime,
      status: fields[3] as String,
      checkIn: fields[4] as DateTime?,
      checkOut: fields[5] as DateTime?,
      notes: fields[6] as String? ?? '',
      updatedAt: fields[7] as DateTime? ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, EmployeeAttendance obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.employeeId)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.checkIn)
      ..writeByte(5)
      ..write(obj.checkOut)
      ..writeByte(6)
      ..write(obj.notes)
      ..writeByte(7)
      ..write(obj.updatedAt);
  }
}
