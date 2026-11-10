// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finance_category.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FinanceCategoryAdapter extends TypeAdapter<FinanceCategory> {
  @override
  final int typeId = 13;

  @override
  FinanceCategory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FinanceCategory(
      id: fields[0] as String,
      name: fields[1] as String,
      kind: fields[2] as String,
      accountId: fields[3] as String,
      active: fields[4] as bool
    );
  }

  @override
  void write(BinaryWriter writer, FinanceCategory obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.kind)
      ..writeByte(3)
      ..write(obj.accountId)
      ..writeByte(4)
      ..write(obj.active);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinanceCategoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
