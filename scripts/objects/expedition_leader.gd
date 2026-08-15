class_name ExpeditionLeader
extends RefCounted

## Data dan keadaan runtime satu pemimpin ekspedisi.
## Cargo disimpan di sini agar tidak hilang ketika berganti kendaraan.

enum Status {
	WAITING,
	TRAVELING,
	TURNING,
	REPAIRING,
}

var leader_id: String = ""
var leader_name: String = "Pemimpin Ekspedisi"
var leader_color: Color = Color.WHITE
var icon_texture: Texture2D = null

var cargo_capacity: int = 6
var cargo_manifest: Array[int] = []

var current_segment_index: int = 0
var is_outbound: bool = true
var status: Status = Status.WAITING
var departure_delay: float = 0.0
var reservation_retry_delay: float = 0.0

var follower: PathFollow2D = null
var current_vehicle: TransportVehicle = null


func _init(
	new_id: String,
	new_name: String,
	new_color: Color,
	new_icon: Texture2D,
	new_capacity: int = 6
) -> void:
	leader_id = new_id
	leader_name = new_name
	leader_color = new_color
	icon_texture = new_icon
	cargo_capacity = new_capacity


func clear_cargo() -> void:
	cargo_manifest.clear()


func get_status_text() -> String:
	match status:
		Status.WAITING:
			return "Menunggu kebutuhan"
		Status.TRAVELING:
			return "Dalam perjalanan"
		Status.TURNING:
			return "Berputar balik"
		Status.REPAIRING:
			return "Dalam perbaikan"
		_:
			return "Tidak diketahui"
