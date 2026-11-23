extends RefCounted
## Brief player-facing meanings shared by mission dialogs and sensor tooltips.
const INPUTS := {
 "SAKELAR_UJI": "Sakelar latihan; aktif ketika operator memilih hidup.",
 "SIANG": "Aktif pada periode siang simulasi (06:00–18:00).",
 "MENDUNG": "Aktif ketika awan tebal menutupi sumber surya.",
 "MINTA_A": "Permintaan sambungan dari petugas A.",
 "MINTA_B": "Permintaan sambungan dari petugas B.",
 "MINTA_POMPA": "Permintaan operator untuk menjalankan pompa.",
 "IZIN_OPERASI": "Izin menjalankan peralatan; bukan permintaan menyalakan.",
 "PERINTAH_UJI": "Keadaan perintah kontaktor pada panel latihan.",
 "STATUS_UJI": "Keadaan kontaktor yang dilaporkan panel latihan.",
 "SUMBER_AIR_ADA": "Menunjukkan air tersedia di sisi masuk pompa.",
 "TANGKI_PENUH": "Aktif saat tangki mencapai batas penuh.",
 "TANGKI_RENDAH": "Aktif saat air tangki berada di batas rendah.",
 "PEMANTAUAN_AKTIF": "Mengaktifkan pengawasan dan pelaporan alarm.",
 "SUHU_TINGGI": "Menunjukkan suhu mesin melewati batas aman.",
 "GANGGUAN_MESIN": "Menunjukkan mesin sedang mengalami gangguan.",
 "GAGAL_START": "Menunjukkan mesin gagal mengikuti permintaan start.",
 "RESET_ALARM": "Tombol operator untuk menghapus alarm yang sudah aman.",
 "AUTO": "Memilih kendali otomatis; nonaktif berarti mode manual.",
 "SAKELAR_MANUAL": "Permintaan diesel dari operator dalam mode manual.",
 "DIESEL_SEHAT": "Menunjukkan diesel tidak mengalami gangguan.",
 "PERINTAH_POMPA": "Sinyal perintah pompa yang sedang dibandingkan dengan statusnya.",
 "STATUS_POMPA": "Umpan balik bahwa pompa benar-benar bekerja.",
 "MODE_PERAWATAN": "Menunjukkan peralatan sedang dirawat.",
 "GANGGUAN_POMPA": "Menunjukkan pompa utama terganggu.",
 "DIESEL_SIAP": "Aktif setelah diesel siap memasok daya; berbeda dari perintah start.",
 "JARINGAN_AMAN": "Frekuensi berada pada rentang aman untuk penyambungan (49,8–50,2 Hz).",
 "MINTA_GILING": "Permintaan menyambungkan penggilingan ke jaringan.",
 "F_RENDAH": "Aktif ketika frekuensi di bawah 49,8 Hz.",
 "F_TINGGI": "Aktif ketika frekuensi di atas 50,2 Hz.",
 "DIESEL_PENUH": "Menunjukkan diesel mendekati kapasitas maksimumnya.",
 "IZIN_PEMUTUSAN": "Izin operator untuk melepas beban gudang.",
 "CADANGAN_CUKUP": "Kapasitas sumber yang siap mampu memasok beban termasuk gudang, ditambah cadangan 5 kW.",
 "PULIHKAN": "Permintaan operator menyambungkan kembali gudang.",
 "GANGGUAN_HIDRO": "Menunjukkan sumber mikrohidro sedang terganggu.",
 "IZIN": "Izin menyambungkan peralatan pada panel latihan."
}
const OUTPUTS := {
 "LAMPU_UJI": "Menyalakan lampu latihan.",
 "LAMPU_HALAMAN": "Mengendalikan lampu halaman desa.",
 "LAMPU_POS": "Mengendalikan lampu pos petugas.",
 "INDIKATOR": "Menyalakan indikator perbedaan perintah dan status.",
 "PERINTAH_POMPA": "Meminta pompa utama bekerja, dengan proteksi peralatan tetap berlaku.",
 "PERINTAH_POMPA_CADANGAN": "Meminta pompa cadangan menggantikan pompa utama.",
 "PERINTAH_DIESEL": "Meminta diesel start atau berhenti; kesiapan dilaporkan terpisah.",
 "SAMBUNG_PENGGILINGAN": "Memerintahkan kontaktor penggilingan tersambung ke jaringan.",
 "PUTUS_GUDANG": "Melepas beban gudang saat aktif; menonaktifkannya memulihkan sambungan.",
 "ALARM": "Menyalakan peringatan kondisi atau gangguan yang perlu diperiksa.",
 "Q": "Perintah sambungan peralatan dari hasil rangkaian panel."
}
static func input_description(key: String) -> String:
	return INPUTS.get(key,"Informasi kondisi atau permintaan operator.")
static func output_description(key: String) -> String:
	return OUTPUTS.get(key,"Perintah kendali ke peralatan desa.")
