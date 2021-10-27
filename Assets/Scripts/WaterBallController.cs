using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class WaterBallController : MonoBehaviour
{
    [SerializeField] private bool isUpdating;
    [SerializeField] private Transform creationPoint;
    [SerializeField] private WaterBall waterballPrefab;
    private WaterBall waterball;
    [SerializeField] private Camera mainCamera;

    void Start()
    {
        if (mainCamera == null) {
            mainCamera = Camera.main;
        }
    }

    // Update is called once per frame
    void Update()
    {
        if (isUpdating) {
            return;
        }

        if (Input.GetMouseButtonDown(0)) {
            if (!IsWaterBallCreated()) {
                CreateWaterBall();
            } else {
                Ray ray = mainCamera.ScreenPointToRay(Input.mousePosition);
                RaycastHit hit;
                if (Physics.Raycast(ray, out hit)) {
                    if (waterball != null) {
                        ThrowWaterBall(hit.point);
                    }
                }
            }
        }
    }

    public bool IsWaterBallCreated()
    {
        return waterball != null;
    }

    public void CreateWaterBall()
    {
        waterball = Instantiate(waterballPrefab, creationPoint.position, Quaternion.identity);
    }

    public void ThrowWaterBall(Vector3 pos)
    {
        waterball.Throw(pos);
    }
}
