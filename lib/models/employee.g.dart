// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employee.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EmployeeAdapter extends TypeAdapter<Employee> {
  @override
  final int typeId = 9;

  @override
  Employee read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Employee(
      id: fields[0] as String,
      name: fields[1] as String,
      type: fields[2] as String,
      wage: fields[3] as double,
      attendance: fields[4] as int,
      salaryPaid: fields[5] as bool,
      employeeCode: fields[6] as String? ?? '',
      phone: fields[7] as String? ?? '',
      email: fields[8] as String? ?? '',
      departmentId: fields[9] as String?,
      designation: fields[10] as String? ?? '',
      joiningDate: fields[11] as DateTime?,
      employmentStatus: fields[12] as String? ?? 'active',
      emergencyContact: fields[13] as String? ?? '',
      address: fields[14] as String? ?? '',
      notes: fields[15] as String? ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, Employee obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.wage)
      ..writeByte(4)
      ..write(obj.attendance)
      ..writeByte(5)
      ..write(obj.salaryPaid)
      ..writeByte(6)
      ..write(obj.employeeCode)
      ..writeByte(7)
      ..write(obj.phone)
      ..writeByte(8)
      ..write(obj.email)
      ..writeByte(9)
      ..write(obj.departmentId)
      ..writeByte(10)
      ..write(obj.designation)
      ..writeByte(11)
      ..write(obj.joiningDate)
      ..writeByte(12)
      ..write(obj.employmentStatus)
      ..writeByte(13)
      ..write(obj.emergencyContact)
      ..writeByte(14)
      ..write(obj.address)
      ..writeByte(15)
      ..write(obj.notes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmployeeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
