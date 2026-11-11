// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finance_account.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FinanceAccountAdapter extends TypeAdapter<FinanceAccount> {
  @override
  final int typeId = 10;

  @override
  FinanceAccount read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FinanceAccount(
      id: fields[0] as String,
      name: fields[1] as String,
      accountType: fields[2] as String,
      parentId: fields[3] as String?,
      currencyCode: fields[4] as String,
      active: fields[5] as bool,
      createdAt: fields[6] as DateTime
    );
  }

  @override
  void write(BinaryWriter writer, FinanceAccount obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.accountType)
      ..writeByte(3)
      ..write(obj.parentId)
      ..writeByte(4)
      ..write(obj.currencyCode)
      ..writeByte(5)
      ..write(obj.active)
      ..writeByte(6)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinanceAccountAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
