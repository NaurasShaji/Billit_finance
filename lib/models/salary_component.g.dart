// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salary_component.dart';

class SalaryComponentAdapter extends TypeAdapter<SalaryComponent> {
  @override
  final int typeId = 18;

  @override
  SalaryComponent read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return SalaryComponent(
      id: fields[0] as String,
      employeeId: fields[1] as String,
      name: fields[2] as String,
      componentType: fields[3] as String,
      amountPaise: fields[4] as int,
      effectiveFrom: fields[5] as DateTime,
      effectiveTo: fields[6] as DateTime?,
      active: fields[7] as bool? ?? true,
    );
  }

  @override
  void write(BinaryWriter writer, SalaryComponent obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.employeeId)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.componentType)
      ..writeByte(4)
      ..write(obj.amountPaise)
      ..writeByte(5)
      ..write(obj.effectiveFrom)
      ..writeByte(6)
      ..write(obj.effectiveTo)
      ..writeByte(7)
      ..write(obj.active);
  }
}
