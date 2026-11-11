// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hr_department.dart';

class HrDepartmentAdapter extends TypeAdapter<HrDepartment> {
  @override
  final int typeId = 15;

  @override
  HrDepartment read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return HrDepartment(
      id: fields[0] as String,
      name: fields[1] as String,
      description: fields[2] as String? ?? '',
      active: fields[3] as bool? ?? true,
      createdAt: fields[4] as DateTime? ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, HrDepartment obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.active)
      ..writeByte(4)
      ..write(obj.createdAt);
  }
}
