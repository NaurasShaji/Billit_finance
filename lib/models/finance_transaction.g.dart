// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finance_transaction.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FinanceTransactionAdapter extends TypeAdapter<FinanceTransaction> {
  @override
  final int typeId = 11;

  @override
  FinanceTransaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FinanceTransaction(
      id: fields[0] as String,
      transactionNumber: fields[1] as String,
      transactionType: fields[2] as String,
      status: fields[3] as String,
      date: fields[4] as DateTime,
      memo: fields[5] as String,
      reference: fields[6] as String,
      sourceType: fields[7] as String,
      sourceId: fields[8] as String,
      createdAt: fields[9] as DateTime,
      postedAt: fields[10] as DateTime?,
      reversedTransactionId: fields[11] as String?
    );
  }

  @override
  void write(BinaryWriter writer, FinanceTransaction obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.transactionNumber)
      ..writeByte(2)
      ..write(obj.transactionType)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.date)
      ..writeByte(5)
      ..write(obj.memo)
      ..writeByte(6)
      ..write(obj.reference)
      ..writeByte(7)
      ..write(obj.sourceType)
      ..writeByte(8)
      ..write(obj.sourceId)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.postedAt)
      ..writeByte(11)
      ..write(obj.reversedTransactionId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinanceTransactionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
